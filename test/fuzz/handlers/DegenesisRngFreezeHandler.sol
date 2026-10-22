// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsLensReader} from "../../../contracts/CrapsLens.sol";

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {Craps} from "../../../contracts/Craps.sol";
import {JackpotBattle} from "../../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../../contracts/storage/CrapsBattleStorage.sol";
import {EntropyLib} from "../../../contracts/libraries/EntropyLib.sol";
import {FlipRoundLib} from "../../../contracts/libraries/FlipRoundLib.sol";
import {CrapsPriceLib} from "../../../contracts/libraries/CrapsPriceLib.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {CrapsViews} from "../../craps/CrapsViews.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";

/// @dev Reference resolution of one Degenesis order from the inputs fixed at its cohort's request
///      (spec §3-§5; the same per-order formula DegenesisHarness models).
library DegenesisOrderRef {
    uint256 internal constant UNIT = 0.0001 ether;
    uint256 internal constant K_UNITS = 460_000;
    uint256 internal constant BONUS_WINDOW = 6 hours;
    uint256 internal constant ORDER_DOMAIN = 0x446567656e657369734f72646572;
    uint256 internal constant CATEGORY_TAG = 0x44656743617465676f7279;
    uint256 internal constant SIZE_TAG = 0x44656753697a65;
    uint256 internal constant PASS_TAG = 0x5061737353696465;
    uint256 internal constant FLIP_ROUND_TAG = 0x466c6970526f756e64;
    uint256 internal constant BOX_PASS_ROUND_TAG = 0x50617373526f756e64;
    uint256 internal constant MAX_UNITS = (uint256(1) << 38) - 1;

    struct Out {
        uint32 id;
        uint256 amount;
        uint256 flip;
        uint256 dgnrs;
        uint256 wwxrp;
        uint32 normalPasses;
        uint32 highPasses;
    }

    function outcome(uint256 word, uint256 day, uint256 index, uint256 lane, uint256 volumeUnits, uint256 q)
        internal
        pure
        returns (Out memory o)
    {
        o.id = uint32(lane);
        uint256 units = (lane >> 32) & MAX_UNITS;
        uint256 secs = lane >> 70;
        if (secs > BONUS_WINDOW) secs = BONUS_WINDOW;
        o.amount = units * UNIT;
        uint256 seed = EntropyLib.hash4(ORDER_DOMAIN, word, (day << 32) | index, o.id);
        uint256 cat = EntropyLib.hash2(seed, CATEGORY_TAG) % 100;
        uint256 size = EntropyLib.hash2(seed, SIZE_TAG);
        if (cat < 50) {
            uint256 roll = size % 20;
            uint256 bps = roll < 16 ? 14_098 + roll * 1158 : 74_534 + (roll - 16) * 22_890;
            uint256 flipOut = (units * UNIT * 1000 * bps * (21 - day) * (453_600 - secs) * K_UNITS)
                / (uint256(10_000) * 16 * 432_000 * (K_UNITS + volumeUnits) * PriceLookupLib.priceForLevel(1));
            if (flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD) {
                flipOut = FlipRoundLib.roundFlipToHundreds(flipOut, EntropyLib.hash2(seed, FLIP_ROUND_TAG));
            }
            if (flipOut == 0) {
                o.wwxrp = 1;
            } else if (EntropyLib.hash2(seed, PASS_TAG) & 1 == 1) {
                bool highPass = flipOut > CrapsPriceLib.HIGH_SWITCH;
                uint256 passUnit = highPass ? CrapsPriceLib.HIGH_VALUE : CrapsPriceLib.NORMAL_VALUE;
                uint256 passCount = flipOut / passUnit;
                uint256 rest;
                if (highPass && passCount >= 12) {
                    passCount = 12;
                    rest = flipOut - 12 * CrapsPriceLib.HIGH_VALUE;
                } else {
                    uint256 rem = flipOut % passUnit;
                    if (rem != 0 && EntropyLib.hash2(seed, BOX_PASS_ROUND_TAG) % passUnit < rem) ++passCount;
                }
                flipOut = rest;
                if (passCount == 0) o.wwxrp = 1;
                else if (highPass) o.highPasses = uint32(passCount);
                else o.normalPasses = uint32(passCount);
            }
            o.flip = flipOut;
        } else if (cat < 90) {
            o.dgnrs = (units * q * (5000 + size % 10_001)) / (volumeUnits * 10_000);
            if (o.dgnrs == 0) o.wwxrp = 1;
        } else {
            o.wwxrp = 1;
        }
    }
}

/// @title DegenesisRngFreezeHandler -- the Degenesis timeline's lane of the RNG-freeze net
/// @notice Interleaves Degenesis buys, ordinary lootbox buys, Craps day entries, nudge attempts,
///         miner calls, VRF fulfilments, delays, admin retries and day changes, against the real
///         protocol deployed on day index 1. Every action records its logs and the handler
///         replays them in order:
///           - DegenesisCohortPriced: the pricing must ride a VRF request made in the same call,
///             bound to that request's day, whose word is not yet recorded. The handler then
///             snapshots every input the cohort's resolution reads: the lanes, V, the count, Q
///             and the bound day.
///           - DailyRngApplied for the bound day: the word the cohort must resolve from.
///           - DegenesisOrderResolved: must be an order of the snapshotted cohort, resolved once,
///             after its word, and equal field for field to the reference computed from the
///             snapshot and that word.
///           - DegenesisCohortClosed: every order of the snapshotted cohort resolved.
///           - JackpotBattleLocked / Started: a locked round's field, price and award target are
///             frozen until it starts; a Degenesis window day draws no awarded seats.
///         After every action the snapshotted cohort's inputs and the copied word are re-read, and
///         the lootbox read buffer sealed by the latest request is re-hashed: neither may change
///         before resolution. Counters below must stay 0; the ghost_* tallies feed the suite's
///         non-vacuity gate.
contract DegenesisRngFreezeHandler is Test {
    bytes32 internal constant SIG_RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant SIG_BUY = keccak256("DegenesisBuy(uint32,uint8,uint32,uint256,uint256)");
    bytes32 internal constant SIG_PRICED = keccak256("DegenesisCohortPriced(uint8,uint256,uint256,uint24)");
    bytes32 internal constant SIG_CLOSED = keccak256("DegenesisCohortClosed(uint8,uint256)");
    bytes32 internal constant SIG_DAILY_APPLIED = keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)");
    bytes32 internal constant SIG_LOCKED = keccak256("JackpotBattleLocked(uint64,uint24,uint256,uint256)");
    bytes32 internal constant SIG_STARTED = keccak256("JackpotBattleStarted(uint64,uint24,uint256,uint256,uint256)");
    uint256 internal constant UNIT = 0.0001 ether;
    uint256 internal constant FLIP_TOP_UP = 5_000_000 ether;

    DegenerusGame public immutable game;
    MockVRFCoordinator public immutable vrf;
    FLIP public immutable coin;
    CrapsViews public immutable craps;
    address[] public actors;

    // ---- properties: each must stay 0 ----
    uint256 public ghost_frozenInputMutations;
    uint256 public ghost_outcomeMismatches;
    uint256 public ghost_doubleResolutions;
    uint256 public ghost_resolvedBeforeWord;
    uint256 public ghost_strayResolutions;
    uint256 public ghost_pricedWithoutRequest;
    uint256 public ghost_boundToKnownWord;
    uint256 public ghost_overlappingPricing;
    uint256 public ghost_closedIncomplete;
    uint256 public ghost_wordCopyMismatches;
    uint256 public ghost_windowOrdersIntoSealedCohort;
    uint256 public ghost_sealedBoxMutations;
    uint256 public ghost_battleFieldMutations;
    uint256 public ghost_battleAwardsDuringSale;
    uint256 public ghost_nudgesInDailyWindow;

    // ---- non-vacuity tallies ----
    uint256 public ghost_cohortsPriced;
    uint256 public ghost_cohortsSettled;
    uint256 public ghost_ordersMatched;
    uint256 public ghost_requests;
    uint256 public ghost_requestsMidSale;
    uint256 public ghost_pricingRequestsWithOrdersPending;
    uint256 public ghost_fulfilments;
    uint256 public ghost_buys;
    uint256 public ghost_buysWhileRequestOpen;
    uint256 public ghost_boxBuys;
    uint256 public ghost_boxBuysWhileRequestOpen;
    uint256 public ghost_delaysWhileRequestOpen;
    uint256 public ghost_retries;
    uint256 public ghost_crapsAttempts;
    uint256 public ghost_crapsEntries;
    uint256 public ghost_battleLocks;
    uint256 public ghost_nudgeAttemptsInDailyWindow;
    uint256 public ghost_frozenChecks;
    uint256 public ghost_boxEpochChecks;

    // ---- the priced cohort's snapshot ----
    bool public snapLive;
    uint8 public snapCohort;
    uint24 public snapBoundDay;
    uint256 public snapQ;
    uint256 public snapHeader;
    bytes32 public snapLanesHash;
    uint256 public snapWord;
    bool public snapWordSeen;
    uint256 public snapResolvedCount;
    uint256[] internal snapLanes;
    mapping(uint256 => bool) internal resolvedKey;

    // ---- the sealed lootbox buffer of the latest request ----
    uint256 internal epochRequest;
    uint48 internal epochBuffer;
    uint256 internal epochCount;
    bytes32 internal epochDigest;

    // ---- the locked jackpot battle ----
    bool internal battleLive;
    uint64 internal battleSlot;
    bytes32 internal battleDigest;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, FLIP coin_, CrapsViews craps_, address[] memory actors_) {
        game = game_;
        vrf = vrf_;
        coin = coin_;
        craps = craps_;
        for (uint256 i; i < actors_.length; ++i) actors.push(actors_[i]);
        // The first check takes the first epoch snapshot.
        epochRequest = type(uint256).max;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =====================================================================
    // Actions
    // =====================================================================

    /// @notice A Degenesis buy of 0.01-0.2099 ETH by a fuzzed actor, when the sale is open and
    ///         its credit covers it.
    function buyDegenesis(uint256 actorSeed, uint256 amountSeed) external {
        address a = actors[actorSeed % actors.length];
        uint256 amount = 0.01 ether + (amountSeed % 2000) * UNIT;
        uint24 today = game.currentDayView();
        if (game.gameOver() || game.livenessTriggered()) return;
        if (today < GameTimeLib.DEGENESIS_START_DAY || today >= GameTimeLib.MAIN_LAUNCH_DAY) return;
        if (game.degenesisCreditOf(a) < amount) return;
        bool open = _requestOpen();
        vm.deal(a, a.balance + amount);
        vm.recordLogs();
        vm.prank(a);
        bool ok;
        try game.buyDegenesisBox{value: amount}(0, amount) {
            ok = true;
            ++ghost_buys;
            if (open) ++ghost_buysWhileRequestOpen;
        } catch {}
        _afterAction(_logsOf(ok), vrf.lastRequestId());
    }

    /// @notice An ordinary custom lootbox buy of 0.01-1 ETH (it also earns Degenesis credit).
    function buyBox(uint256 actorSeed, uint256 amountSeed) external {
        address a = actors[actorSeed % actors.length];
        uint256 amount = (10 + amountSeed % 991) * 0.001 ether;
        if (game.gameOver()) return;
        bool open = _requestOpen();
        vm.deal(a, a.balance + amount);
        vm.recordLogs();
        vm.prank(a);
        bool ok;
        try game.purchase{value: amount}(0, 0, BoxOrderLib.boCustom(amount), bytes32(0), MintPaymentKind.DirectEth, false) {
            ok = true;
            ++ghost_boxBuys;
            if (open) ++ghost_boxBuysWhileRequestOpen;
        } catch {}
        _afterAction(_logsOf(ok), vrf.lastRequestId());
    }

    /// @notice A Craps entry by a fuzzed actor on an open window day: the whole day in the first
    ///         window, else the current window (FLIP minted to it).
    function crapsEnter(uint256 actorSeed, uint256 boardSeed) external {
        address a = actors[actorSeed % actors.length];
        if (game.gameOver()) return;
        (uint24 opened,) = craps.bonusDayOf();
        uint24 d = craps.currentDayIndex();
        if (opened != d || craps.dailyWordAt(opened) == 0) return;
        if (craps.daySeatNumberOf(d, a) != 0) return;
        ++ghost_crapsAttempts;
        if (coin.balanceOf(a) < FLIP_TOP_UP / 2) {
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(a, FLIP_TOP_UP);
        }
        (, uint256 period,) = craps.currentBonusSlot();
        vm.recordLogs();
        vm.prank(a);
        bool ok;
        if (period == 0) {
            try craps.enterBonusDay(_board(boardSeed), 1) returns (uint256) {
                ok = true;
                ++ghost_crapsEntries;
            } catch {}
        } else {
            try craps.enterBonusBattle(period, _board(boardSeed), 1) returns (uint256) {
                ok = true;
                ++ghost_crapsEntries;
            } catch {}
        }
        _afterAction(_logsOf(ok), vrf.lastRequestId());
    }

    /// @notice A nudge attempt while the daily window is open: it must be refused.
    function tryNudge(uint256 actorSeed) external {
        if (!game.rngLocked() || game.gameOver()) return;
        address a = actors[actorSeed % actors.length];
        (, uint256 cost) = game.rngNudgeQuote();
        if (cost == 0) return;
        if (coin.balanceOf(a) < cost) {
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(a, cost + FLIP_TOP_UP);
        }
        ++ghost_nudgeAttemptsInDailyWindow;
        vm.recordLogs();
        vm.prank(a);
        bool ok;
        try game.reverseFlip(cost) {
            ok = true;
            ++ghost_nudgesInDailyWindow;
        } catch {}
        _afterAction(_logsOf(ok), vrf.lastRequestId());
    }

    /// @notice One miner call on a fuzzed gas budget (2M-32M, or unbounded), from a fuzzed caller.
    function mine(uint256 gasSeed, uint256 callerSeed) external {
        if (game.gameOver() && game.isFinalSwept()) return;
        uint256 req0 = vrf.lastRequestId();
        uint256 g = gasSeed % 5 == 0 ? 0 : 2_000_000 + (gasSeed % 30) * 1_000_000;
        address caller = address(uint160(uint256(keccak256(abi.encode("deg-rng-miner", callerSeed % 7)))));
        vm.recordLogs();
        vm.prank(caller);
        bool ok;
        if (g == 0) {
            try game.mineFlip(0) {
                ok = true;
            } catch {}
        } else {
            try game.mineFlip{gas: g}(0) {
                ok = true;
            } catch {}
        }
        _afterAction(_logsOf(ok), req0);
    }

    /// @notice Up to `n` (1-12) miner calls, stopping at idle. Half the seeds stop at an
    ///         unanswered request too; the other half run a live keeper that answers each request
    ///         (a fuzzed word) before the next call.
    function crank(uint256 nSeed) external {
        uint256 n = 1 + nSeed % 12;
        bool answer = (nSeed >> 8) & 1 == 1;
        for (uint256 i; i < n; ++i) {
            if (game.gameOver() && game.isFinalSwept()) return;
            if (answer) _answerOpen(uint256(keccak256(abi.encode(nSeed, i))));
            uint256 req0 = vrf.lastRequestId();
            vm.recordLogs();
            bool ok;
            try game.mineFlip(0) {
                ok = true;
            } catch {}
            _afterAction(_logsOf(ok), req0);
            if (!ok && !(answer && _requestOpen())) return;
        }
    }

    /// @dev Answer the latest request if it is open, replaying the callback's logs.
    function _answerOpen(uint256 wordSeed) internal {
        uint256 req = vrf.lastRequestId();
        if (req == 0) return;
        (,, bool done) = vrf.pendingRequests(req);
        if (done) return;
        vm.recordLogs();
        bool ok;
        try vrf.fulfillRandomWords(req, uint256(keccak256(abi.encode("deg-rng-word", wordSeed, req)))) {
            ok = true;
            ++ghost_fulfilments;
        } catch {}
        _afterAction(_logsOf(ok), req);
    }

    /// @notice Answer the open request with a fuzzed word.
    function fulfil(uint256 wordSeed) external {
        _answerOpen(wordSeed);
    }

    /// @notice Let 1-5 hours pass (several in a row cross a day uncranked: a gap day).
    function delay(uint256 secsSeed) external {
        if (_requestOpen()) ++ghost_delaysWhileRequestOpen;
        vm.warp(block.timestamp + 1 hours + secsSeed % 4 hours);
        vm.recordLogs();
        _afterAction(vm.getRecordedLogs(), vrf.lastRequestId());
    }

    /// @notice Move to the next day, 0-3 hours in, once today's daily word has been applied
    ///         (so the campaign spends its depth on the sale rather than skipping past it). While a
    ///         cohort whose word has landed is still settling, three seeds in four wait for it; the
    ///         fourth moves on and leaves a backlog across the next request.
    function nextDay(uint256 secsSeed) external {
        uint24 d = game.currentDayView();
        if (uint24(_load(GameSlots.DAILY_IDX) >> (GameSlots.DAILY_IDX_OFFSET * 8)) < d) return;
        if (_word() != 0 && secsSeed % 4 != 0) return;
        vm.warp(uint256(d) * 1 days + GameTimeLib.JACKPOT_RESET_TIME + secsSeed % 3 hours);
        vm.recordLogs();
        _afterAction(vm.getRecordedLogs(), vrf.lastRequestId());
    }

    /// @notice Stall the open request past the retry timeout and re-issue it through the admin.
    function stallAndRetry() external {
        if (!_requestOpen() || game.gameOver() || game.livenessTriggered()) return;
        vm.warp(block.timestamp + 20 hours + 1);
        uint256 req0 = vrf.lastRequestId();
        vm.recordLogs();
        vm.prank(ContractAddresses.ADMIN);
        bool ok;
        try game.retryRng() {
            ok = true;
            ++ghost_retries;
        } catch {}
        _afterAction(_logsOf(ok), req0);
    }

    /// @notice End-of-run drain (excluded from the campaign): answer every request and mine
    ///         until the engine idles, without moving the clock, replaying every call. A cohort
    ///         whose word has landed must settle here.
    function drainAll() external {
        for (uint256 i; i < 400; ++i) {
            if (game.gameOver() && game.isFinalSwept()) return;
            _answerOpen(uint256(keccak256(abi.encode("deg-rng-drain", i))));
            uint256 req0 = vrf.lastRequestId();
            vm.recordLogs();
            bool ok;
            try game.mineFlip(0) {
                ok = true;
            } catch {}
            _afterAction(_logsOf(ok), req0);
            if (!ok && !_requestOpen()) return;
        }
    }

    // =====================================================================
    // Log replay and checks
    // =====================================================================

    /// @dev The recorded logs of a call that succeeded; a reverted call's logs are dropped (forge
    ///      keeps logs emitted inside a call that later reverted, and the call changed no state).
    function _logsOf(bool ok) internal returns (Vm.Log[] memory logs) {
        logs = vm.getRecordedLogs();
        if (!ok) logs = new Vm.Log[](0);
    }

    function _afterAction(Vm.Log[] memory logs, uint256 reqBefore) internal {
        bool requested = vrf.lastRequestId() != reqBefore;
        if (requested) {
            ++ghost_requests;
        }
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length == 0) continue;
            bytes32 t = l.topics[0];
            if (l.emitter == address(game)) {
                if (t == SIG_DAILY_APPLIED) _onDailyApplied(l);
                else if (t == SIG_PRICED) _onPriced(l, requested);
                else if (t == SIG_RESOLVED) _onResolved(l);
                else if (t == SIG_CLOSED) _onClosed(l);
                else if (t == SIG_BUY) _onBuy(l);
            } else if (l.emitter == address(craps)) {
                if (t == SIG_LOCKED) _onLocked(l);
                else if (t == SIG_STARTED) _onStarted(l);
            }
        }
        _checkFrozen();
        _checkBoxEpoch();
        _checkBattle();
    }

    function _onDailyApplied(Vm.Log memory l) internal {
        (uint24 day,,, uint256 fin) = abi.decode(l.data, (uint24, uint256, uint256, uint256));
        if (snapLive && day == snapBoundDay) {
            snapWord = fin;
            snapWordSeen = true;
        }
    }

    function _onPriced(Vm.Log memory l, bool requested) internal {
        uint8 c = uint8(uint256(l.topics[1]));
        (uint256 volume, uint256 q, uint24 bound) = abi.decode(l.data, (uint256, uint256, uint24));
        if (!requested || _rngRequestDay() != bound) ++ghost_pricedWithoutRequest;
        if (game.rngWordForDay(bound) != 0) ++ghost_boundToKnownWord;
        if (snapLive) ++ghost_overlappingPricing;
        ++ghost_cohortsPriced;
        if (bound > GameTimeLib.DEGENESIS_START_DAY && bound <= GameTimeLib.MAIN_LAUNCH_DAY) ++ghost_requestsMidSale;

        snapLive = true;
        snapCohort = c;
        snapBoundDay = bound;
        snapQ = q;
        snapHeader = _header(c);
        snapWord = 0;
        snapWordSeen = false;
        snapResolvedCount = 0;
        delete snapLanes;
        uint256 count = uint32(snapHeader >> 48);
        for (uint256 i; i < count; ++i) snapLanes.push(_lane(c, i));
        snapLanesHash = _lanesHash(c, count);
        if (count != 0) ++ghost_pricingRequestsWithOrdersPending;
        if (uint48(snapHeader) * UNIT != volume || _activeQ() != q || _activeDay() != bound) ++ghost_frozenInputMutations;
    }

    function _onResolved(Vm.Log memory l) internal {
        uint32 id = uint32(uint256(l.topics[1]));
        (uint8 day, uint32 index, uint256 amount, uint256 flip, uint256 dgnrs, uint256 wwxrp, uint32 np, uint32 hp) =
            abi.decode(l.data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
        if (!snapLive || day != snapCohort || index >= snapLanes.length) {
            ++ghost_strayResolutions;
            return;
        }
        if (!snapWordSeen) ++ghost_resolvedBeforeWord;
        uint256 key = (uint256(day) << 32) | index;
        if (resolvedKey[key]) ++ghost_doubleResolutions;
        resolvedKey[key] = true;
        ++snapResolvedCount;
        DegenesisOrderRef.Out memory o = DegenesisOrderRef.outcome(
            snapWord, day, index, snapLanes[index], uint48(snapHeader), snapQ
        );
        if (o.id != id || o.amount != amount || o.flip != flip || o.dgnrs != dgnrs || o.wwxrp != wwxrp
            || o.normalPasses != np || o.highPasses != hp) {
            ++ghost_outcomeMismatches;
        } else {
            ++ghost_ordersMatched;
        }
    }

    function _onClosed(Vm.Log memory l) internal {
        uint8 c = uint8(uint256(l.topics[1]));
        if (!snapLive || c != snapCohort) return;
        if (snapResolvedCount != snapLanes.length && !game.gameOver() && !game.livenessTriggered()) {
            ++ghost_closedIncomplete;
        }
        if (snapLanes.length != 0 && snapResolvedCount == snapLanes.length) ++ghost_cohortsSettled;
        snapLive = false;
    }

    function _onBuy(Vm.Log memory l) internal {
        (uint8 c,,,) = abi.decode(l.data, (uint8, uint32, uint256, uint256));
        // An order only ever joins today's cohort, never a sealed (or priced) one.
        if (uint256(c) != uint256(game.currentDayView()) - GameTimeLib.DEGENESIS_START_DAY + 1) {
            ++ghost_windowOrdersIntoSealedCohort;
        }
        if (snapLive && c == snapCohort) ++ghost_windowOrdersIntoSealedCohort;
    }

    function _onLocked(Vm.Log memory l) internal {
        uint64 slot = uint64(uint256(l.topics[1]));
        (CrapsBattleStorage.JackpotRound memory r,,) = CrapsLensReader.jackpotBattleOf(address(craps), slot);
        ++ghost_battleLocks;
        if (slot / 8 < GameTimeLib.MAIN_LAUNCH_DAY && r.awardTarget != 0) ++ghost_battleAwardsDuringSale;
        battleLive = true;
        battleSlot = slot;
        battleDigest = _roundDigest(r);
    }

    function _onStarted(Vm.Log memory l) internal {
        uint64 slot = uint64(uint256(l.topics[1]));
        (, uint256 drawn,,) = abi.decode(l.data, (uint24, uint256, uint256, uint256));
        if (slot / 8 < GameTimeLib.MAIN_LAUNCH_DAY && drawn != 0) ++ghost_battleAwardsDuringSale;
        if (battleLive && slot == battleSlot) battleLive = false;
    }

    /// @dev The snapshotted cohort's inputs and the copied word, re-read after every action.
    function _checkFrozen() internal {
        if (!snapLive) return;
        if (game.gameOver() || game.livenessTriggered()) {
            snapLive = false;
            return;
        }
        ++ghost_frozenChecks;
        uint256 count = snapLanes.length;
        if (_header(snapCohort) != snapHeader || _lanesHash(snapCohort, count) != snapLanesHash
            || _activeQ() != snapQ || _activeDay() != snapBoundDay || _closed() + 1 != snapCohort) {
            ++ghost_frozenInputMutations;
        }
        uint256 w = _word();
        if (w != 0 && (!snapWordSeen || w != snapWord)) ++ghost_wordCopyMismatches;
        if (snapWordSeen && w == 0) ++ghost_wordCopyMismatches;
    }

    /// @dev The read buffer sealed by the latest request keeps its entries until the next request.
    function _checkBoxEpoch() internal {
        if (game.gameOver() || game.livenessTriggered()) return;
        uint256 req = vrf.lastRequestId();
        uint48 buf = _readBuffer();
        uint256 count = _readCount();
        if (req != epochRequest) {
            epochRequest = req;
            epochBuffer = buf;
            epochCount = count;
            epochDigest = _bufferDigest(buf, count);
            return;
        }
        ++ghost_boxEpochChecks;
        if (buf != epochBuffer || count != epochCount || _bufferDigest(buf, count) != epochDigest) {
            ++ghost_sealedBoxMutations;
        }
    }

    function _checkBattle() internal {
        if (!battleLive) return;
        (CrapsBattleStorage.JackpotRound memory r,,) = CrapsLensReader.jackpotBattleOf(address(craps), battleSlot);
        if (r.started) {
            battleLive = false;
            return;
        }
        if (_roundDigest(r) != battleDigest) ++ghost_battleFieldMutations;
    }

    function _roundDigest(CrapsBattleStorage.JackpotRound memory r) internal pure returns (bytes32) {
        return keccak256(abi.encode(r.paidCount, r.paidUnits, r.awardTarget, r.entryPrice, r.added, r.requestDay, r.level));
    }

    // =====================================================================
    // Storage readers
    // =====================================================================

    function _load(uint256 slot) internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(slot)));
    }

    function _requestOpen() internal view returns (bool) {
        return _load(0) & (uint256(1) << 254) != 0 && _load(GameSlots.RNG_WORD_CURRENT) == 1;
    }

    function _rngRequestDay() internal view returns (uint24) {
        return uint24(_load(GameSlots.RNG_REQUEST_DAY));
    }

    function _closed() internal view returns (uint8) {
        return uint8(_load(GameSlots.DEGENESIS_CLOSED) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }

    function _active() internal view returns (uint256) {
        return _load(GameSlots.DEGENESIS_ACTIVE);
    }

    function _activeQ() internal view returns (uint256) {
        return _active() & ((uint256(1) << 80) - 1);
    }

    function _activeDay() internal view returns (uint24) {
        return uint24(_active() >> 160);
    }

    function _word() internal view returns (uint256) {
        return _load(GameSlots.DEGENESIS_WORD);
    }

    function _header(uint256 c) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
    }

    function _orderSlot(uint256 c, uint256 s) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode((c << 32) | s, GameSlots.DEGENESIS_ORDERS))));
    }

    function _lane(uint256 c, uint256 index) internal view returns (uint256) {
        return (_orderSlot(c, index / 3) >> ((index % 3) * 85)) & ((uint256(1) << 85) - 1);
    }

    function _lanesHash(uint256 c, uint256 count) internal view returns (bytes32 h) {
        for (uint256 s; s < (count + 2) / 3; ++s) h = keccak256(abi.encode(h, _orderSlot(c, s)));
    }

    function _readBuffer() internal view returns (uint48) {
        uint256 flags = uint16(_load(0) >> (GameSlots.RNG_FLAGS_AND_NUDGES_OFFSET * 8));
        return uint48(((flags >> 12) & 1) ^ 1);
    }

    function _readCount() internal view returns (uint256) {
        return uint32(_load(GameSlots.BOX_READ_COUNT) >> (GameSlots.BOX_READ_COUNT_OFFSET * 8));
    }

    function _bufferDigest(uint48 buf, uint256 count) internal view returns (bytes32 h) {
        bytes32 base = keccak256(abi.encode(bytes32(GameSlots.BOX_QUEUE + uint256(buf))));
        for (uint256 i; i < (count + 2) / 3; ++i) {
            h = keccak256(abi.encode(h, vm.load(address(game), bytes32(uint256(base) + i))));
        }
    }

    function _board(uint256 seed) internal pure returns (Craps.Bets memory b) {
        uint24 count = uint24(1 + seed % 7);
        uint24 first = count > 3 ? 3 : count;
        uint24 rest = count - first;
        uint24 second = rest > 3 ? 3 : rest;
        uint24 third = rest - second;
        uint256 shape = (seed >> 3) % 3;
        if (shape == 0) {
            b.place4 = first;
            b.place10 = second;
            b.place5 = third;
        } else if (shape == 1) {
            b.passLine = first;
            b.place4 = second;
            b.place10 = third;
        } else {
            b.place6 = first;
            b.hard8 = second;
            b.place8 = third;
        }
    }

    // =====================================================================
    // Falsifiability seams (excluded from the campaign)
    // =====================================================================

    /// @notice Overwrite one order slot of the live snapshotted cohort and run the frozen-input
    ///         check; returns whether it fired. Restores the slot and the counter.
    function debugSeedLaneMutationAndCheck() external returns (bool detected) {
        if (!snapLive || snapLanes.length == 0) return false;
        bytes32 slot = keccak256(abi.encode(uint256(snapCohort) << 32, GameSlots.DEGENESIS_ORDERS));
        bytes32 old = vm.load(address(game), slot);
        uint256 before = ghost_frozenInputMutations;
        vm.store(address(game), slot, bytes32(uint256(old) ^ (uint256(1) << 40)));
        _checkFrozen();
        detected = ghost_frozenInputMutations > before;
        vm.store(address(game), slot, old);
        ghost_frozenInputMutations = before;
    }

    /// @notice Feed one resolution the replay must reject: the first order of the snapshotted
    ///         cohort with its FLIP off by one. Returns whether the mismatch counter moved;
    ///         restores the counters and the resolved mark.
    function debugSeedOutcomeMismatchAndCheck() external returns (bool detected) {
        if (!snapLive || snapLanes.length == 0 || !snapWordSeen) return false;
        DegenesisOrderRef.Out memory o =
            DegenesisOrderRef.outcome(snapWord, snapCohort, 0, snapLanes[0], uint48(snapHeader), snapQ);
        Vm.Log memory l;
        l.emitter = address(game);
        l.topics = new bytes32[](2);
        l.topics[0] = SIG_RESOLVED;
        l.topics[1] = bytes32(uint256(o.id));
        l.data = abi.encode(snapCohort, uint32(0), o.amount, o.flip + 1, o.dgnrs, o.wwxrp, o.normalPasses, o.highPasses);
        uint256 key = uint256(snapCohort) << 32;
        bool wasResolved = resolvedKey[key];
        uint256 mm = ghost_outcomeMismatches;
        uint256 dbl = ghost_doubleResolutions;
        uint256 matched = ghost_ordersMatched;
        uint256 rc = snapResolvedCount;
        _onResolved(l);
        detected = ghost_outcomeMismatches > mm;
        ghost_outcomeMismatches = mm;
        ghost_doubleResolutions = dbl;
        ghost_ordersMatched = matched;
        snapResolvedCount = rc;
        resolvedKey[key] = wasResolved;
    }
}
