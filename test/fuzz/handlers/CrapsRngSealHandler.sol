// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../../helpers/RecyclingState.sol";

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {Coinflip} from "../../../contracts/Coinflip.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {Craps} from "../../../contracts/Craps.sol";
import {CrapsBattle} from "../../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {JackpotBattle} from "../../../contracts/JackpotBattle.sol";
import {CrapsViews} from "../../craps/CrapsViews.sol";

/// @title CrapsRngSealHandler — the craps lane of the RNG-freeze net, driven against the REAL
///        protocol (real game, real FLIP burn gate, real Coinflip credit lane, real VRF lifecycle).
///
/// @notice The craps table binds every field to a lootbox-RNG index at the moment the field shuts
///         (`_armSlot` takes `_writeBuffer()`, the table whose word cannot exist yet) and reads
///         that index's word at settlement through `LootboxCraps._wordAt`. The static RNG-window
///         gate classifies those reads CONSUMER-SEALED; the craps conservation campaign drives the
///         table against mocks with words seeded by hand. Nothing exercised the seal against the
///         request/fulfil machinery that actually produces the words. This handler does: the
///         fuzzer walks entries, amendments, arms, custom battles, keeper cranks, settlements and
///         the exempt VRF machinery (day rollover, fulfilment) in random order, and four ghost
///         counters record every way the seal could break.
///
/// @dev THE PROPERTIES (each counter must stay 0):
///        (1) ghost_armsOnWordedIndex        — a field shut onto an index whose word already existed.
///        (2) ghost_armsBelowCursor          — a field shut onto an index at or below the reserved
///                                             region (`index < LR_INDEX` at arm: a leaf some request
///                                             has already claimed).
///        (3) ghost_inFlightLandedOnArmedIndex — a request that was in flight when a field shut later
///                                             fulfilled INTO that field's index (the dice would have
///                                             been requested before the field was frozen).
///        (4) ghost_postArmSlipMutations     — a slip's stored board, seat or standing changed after
///                                             its field shut (an amendment landed on a frozen field).
///        (5) ghost_settlesWithoutWord       — a settlement advanced the resolution cursor while the
///                                             field's word was still zero.
///        (6) ghost_inWindowGameSetMutations — a craps action taken while a protocol VRF window was
///                                             open (daily lock OR mid-day request in flight) moved
///                                             any slot of the game's enumerated consumed set. The
///                                             craps arm makes no request of its own; the ordinary
///                                             request that seals a shut window is refused inside
///                                             either window, so no craps door may touch the set.
///
///      ISOLATION. Every craps action snapshots the game's enumerated set immediately before and
///      re-reads it immediately after the call alone; the exempt machinery (mineFlip, the VRF
///      callback, and the arm's request when NO window is open) is never measured.
///
///      NON-VACUITY. The invariant's afterInvariant gates on days opened, arms, arms taken while a
///      window was open, post-arm amendment attempts, and settlements on real words — a run in
///      which the seal was never tested fails.
///
///      Test-only: NO contracts/*.sol is mutated. The only vm.store lives in the falsifiability
///      seam, which the campaign excludes.
contract CrapsRngSealHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    FLIP public coin;
    CrapsViews public craps;
    Coinflip public coinflip;
    DegenerusVault public vault;

    // -------------------------------------------------------------------------
    // Game storage layout (the RngWindowFreezeHandler constants — same authority)
    // -------------------------------------------------------------------------
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 3;
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;
    uint256 private constant LR_MID_DAY_SHIFT = 224;
    uint256 private constant LR_MID_DAY_MASK = 0xFF;
    uint256 private constant VRF_REQUEST_ID_SLOT = 4;
    uint256 private constant DAILY_IDX_BYTE_OFF = 3;
    uint256 private constant RNG_REQUEST_TIME_BYTE_OFF = 6;
    uint256 private constant RNG_REQUEST_TIME_MASK = 0xFFFFFFFFFFFF;
    uint256 private constant RNG_LOCKED_FLAG_BYTE_OFF = 19;
    uint256 private constant TICKET_WRITE_SLOT_BYTE_OFF = 26;

    // -------------------------------------------------------------------------
    // Craps schedule shape
    // -------------------------------------------------------------------------
    uint256 internal constant PERIODS = 7;
    uint256 internal constant SLOTS_PER_DAY = 8;
    uint256 internal constant CUSTOM_SLOT_BASE = 1 << 40;
    uint256 internal constant FLIP_TOP_UP = 1_000_000 ether;
    uint256 internal constant FLIP_FLOOR = 50_000 ether;

    address[] public actors;
    address internal currentActor;

    // -------------------------------------------------------------------------
    // Tracked state
    // -------------------------------------------------------------------------
    uint64[] public trackedSlots; // every window / custom slot an entry bound to
    mapping(uint64 => bool) internal slotSeen;
    mapping(uint64 => uint256[]) internal slotBets;
    uint256[] public betIds;

    uint64[] public armedSlots;
    mapping(uint64 => bool) internal armedSeen;
    mapping(uint64 => uint48) public armedIndexOf;
    mapping(uint64 => uint256) public inFlightReqAtArm; // unfulfilled request id at arm, else 0
    mapping(uint256 => bytes32) public sealedHeader; // betId => hash of the frozen slip fields
    mapping(uint64 => uint256) public customCloseOf; // custom slot => its close time

    uint24 internal lastOpenedDay;
    uint24 internal firstOpenedDay;
    /// @dev The earliest craps day seen open by any engine crank (the keeper bound's range start).
    ///      Kept apart from first/lastOpenedDay, whose bookkeeping drives the subsidy ghosts.
    uint24 internal boundFirstDay;

    /// @notice Test-only knob (CrapsRealWiringConservation): settle each delivered cohort's
    ///         read-bound Craps fields through the measured keeper door instead of inside an engine
    ///         crank, where the table's credits cannot be isolated from the crank's other coinflip
    ///         effects. Off by default, so the RNG seal campaign's crank is unchanged.
    bool public measureTableSettlement;

    // -------------------------------------------------------------------------
    // Ghost surface — THE PROPERTIES (must stay 0)
    // -------------------------------------------------------------------------
    uint256 public ghost_armsOnWordedIndex;
    uint256 public ghost_armsBelowCursor;
    uint256 public ghost_inFlightLandedOnArmedIndex;
    uint256 public ghost_postArmSlipMutations;
    uint256 public ghost_settlesWithoutWord;
    uint256 public ghost_inWindowGameSetMutations;

    // -------------------------------------------------------------------------
    // Ghost surface — non-vacuity and surveillance
    // -------------------------------------------------------------------------
    uint256 public ghost_daysOpened;
    uint256 public ghost_entries;
    uint256 public ghost_dayTickets;
    uint256 public ghost_customBattles;
    uint256 public ghost_arms;
    uint256 public ghost_armsWhileDailyLocked;
    uint256 public ghost_armsWhileMidDayInFlight;
    uint256 public ghost_sealRequests; // an ordinary request sealed a pending craps window's buffer
    uint256 public ghost_postArmAmendAttempts;
    uint256 public ghost_postArmAmendsAccepted;
    uint256 public ghost_settlesWithWord;
    uint256 public ghost_settleAttemptsWithoutWord;
    uint256 public ghost_inWindowCrapsActions;
    uint256 public ghost_midDayInWindowCrapsActions;
    uint256 public ghost_fulfilments;
    uint256 public ghost_keeps;
    /// @dev Keeper cranks that REVERTED. The game's craps leg calls `keepScheduled` bare, so a
    ///      revert here at unbounded gas is a revert the crank would take down with it.
    uint256 public ghost_keepReverts;
    uint256 public ghost_wordsLandedOnArmedIndices;

    // -------------------------------------------------------------------------
    // Ghost surface — the FLIP ledger through the REAL ring (CrapsRealWiringConservation)
    // -------------------------------------------------------------------------
    /// @notice FLIP burned into the table by every entrant and by the two protocol bodies' seats.
    uint256 public ghost_flipBurnedIn;
    /// @notice Protocol money each opened day made spendable: the ladder budget, the progressive
    ///         contribution and the high-lane budget, read at the open.
    uint256 public ghost_subsidies;
    /// @notice The value of every protocol seat that was paid with a banked pass rather than a
    ///         burn: seats x that day's bill (each window's bankroll + bounty).
    uint256 public ghost_passSeatValue;
    /// @notice Coinflip stake credited by settlements and keeper cranks (measured in isolation
    ///         around each settling call, so the coinflip's own daily resolution never pollutes it).
    uint256 public ghost_creditedOut;
    /// @notice THE PROPERTY. Settling calls whose credited stake exceeded the settlement's own
    ///         liability bound: every seat's engine-priced return (`settlementOn`, day tickets and
    ///         the protocol bodies included) plus the field's pooled stake (the high lane's pooled
    ///         principal included), the window's boost ceilings — a hundred times the advertised
    ///         main and high bases, the table's own top rung — and the progressive balance —
    ///         every source a payout can draw from. Must stay 0.
    uint256 public ghost_creditsOverBound;
    uint256 public ghost_lastOverCredited;
    uint256 public ghost_lastOverBound;
    uint256 public ghost_lastOverSlot;
    bool public ghost_lastOverWasKeep;
    /// @notice Vault comps granted through the real vault (its lifetime cap is two hundred).
    uint256 public ghost_compsGranted;
    uint256 public ghost_compGrantsRefused;
    /// @dev FLIP wei the comp lane was charged by grants this handler made.
    uint256 public ghost_compLaneSpent;

    modifier useActor(uint256 seed) {
        currentActor = actors[seed % actors.length];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, FLIP coin_, CrapsViews craps_, uint256 actorCount_) {
        game = game_;
        vrf = vrf_;
        coin = coin_;
        craps = craps_;
        coinflip = Coinflip(ContractAddresses.COINFLIP);
        vault = DegenerusVault(payable(ContractAddresses.VAULT));
        // Custom battles open only for an allowed creator (JackpotBattle.setBattleCreator, vault
        // owner only); allow the deployer so the custom-battle door is actually exercised.
        vm.prank(ContractAddresses.CREATOR);
        JackpotBattle(address(craps_)).setBattleCreator(ContractAddresses.CREATOR, true);
        for (uint256 i; i < actorCount_; i++) {
            address a = address(uint160(uint256(keccak256(abi.encode("craps-seal-actor", i)))));
            actors.push(a);
            vm.deal(a, 2_000 ether);
        }
    }

    function setMeasureTableSettlement(bool on) external {
        measureTableSettlement = on;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function trackedSlotCount() external view returns (uint256) {
        return trackedSlots.length;
    }

    function armedSlotCount() external view returns (uint256) {
        return armedSlots.length;
    }

    function betCount() external view returns (uint256) {
        return betIds.length;
    }

    // =========================================================================
    // Exempt machinery: the day rollover (daily request → fulfil → apply → openBonusDay)
    // =========================================================================

    /// @notice Roll the protocol one day forward through the REAL heartbeat so the craps day opens
    ///         on the crank that applied its word. Never measured against the properties.
    function advanceDay(uint256 actorSeed) external useActor(actorSeed) {
        _driveDay(actorSeed);
    }

    function _driveDay(uint256 seed) internal returns (bool opened) {
        if (game.gameOver()) return false;
        _finishHumanRead();
        // A daily window left open by openDailyWindow is completed first (exempt machinery).
        for (uint256 i; i < 4 && game.rngLocked(); i++) {
            _fulfilPending(seed + 100 + i);
            _crank(false);
        }
        // Both lanes: the house banks its level cut as HIGH passes and the seat spends those first.
        (uint256 hbn, uint256 hbh) = craps.passCreditsOf(ContractAddresses.SDGNRS);
        (uint256 vbn, uint256 vbh) = craps.passCreditsOf(ContractAddresses.VAULT);
        uint256 hb = hbn + hbh;
        uint256 vb = vbn + vbh;
        uint256 bodiesFlip = coin.balanceOf(ContractAddresses.SDGNRS) + coin.balanceOf(ContractAddresses.VAULT);
        // Early in the new day: period 0 (the twenty-minute opener) is still taking bets.
        vm.warp(_dayStart() + 1 days + 5 minutes);
        _buyTicket();
        _crank(true);
        for (uint256 i; i < 8; i++) {
            _fulfilPending(seed + i);
            _crank(true);
            if (!game.rngLocked() && _crapsDayOpen()) break;
        }
        _finishHumanRead();
        opened = _crapsDayOpen();
        if (opened) {
            uint24 today = craps.currentDayIndex();
            if (today != lastOpenedDay) {
                if (firstOpenedDay == 0) firstOpenedDay = today;
                lastOpenedDay = today;
                ghost_daysOpened++;
                // What the protocol put on the table for this day, read at the open.
                ghost_subsidies += craps.boostBudgetOf(today) + craps.progressiveContributionFor(today)
                    + craps.highBudgetOf(today);
                // Protocol seats: a spent pass is value the bodies did not burn.
                (uint256 han, uint256 hah) = craps.passCreditsOf(ContractAddresses.SDGNRS);
                (uint256 van, uint256 vah) = craps.passCreditsOf(ContractAddresses.VAULT);
                uint256 passSeats = (hb - (han + hah)) + (vb - (van + vah));
                if (passSeats != 0) ghost_passSeatValue += passSeats * _dayBill(today);
            }
        }
        uint256 bodiesAfter = coin.balanceOf(ContractAddresses.SDGNRS) + coin.balanceOf(ContractAddresses.VAULT);
        if (bodiesAfter < bodiesFlip) ghost_flipBurnedIn += bodiesFlip - bodiesAfter;
        _noteOpenedDay();
        _checkSealedHeaders();
    }

    /// @dev Record the table's own opened-day latch: the crank can open a day on any advance the
    ///      fuzzer drives (openDailyWindow + fulfil), not only inside _driveDay.
    function _noteOpenedDay() internal {
        (uint24 od,) = craps.bonusDayOf();
        if (od == 0) return;
        if (firstOpenedDay == 0 || od < firstOpenedDay) firstOpenedDay = od;
        if (od > lastOpenedDay) lastOpenedDay = od;
    }

    /// @dev One body's day bill: every window's bankroll and bounty — what `_seatBody` burns when
    ///      FLIP pays for the seat.
    function _dayBill(uint24 day) internal view returns (uint256 bill) {
        for (uint256 p; p < PERIODS; p++) {
            (uint128 bankroll,,, uint256 bounty,,) = craps.bonusTermsFor(day, p);
            bill += uint256(bankroll) + bounty;
        }
    }

    /// @notice Deliver the pending VRF word (daily or lootbox lane) and let the heartbeat consume
    ///         it. This is where property (3) is measured: a request that was in flight when a
    ///         field shut must never fulfil into that field's index.
    function fulfil(uint256 wordSeed) external {
        _fulfilPending(wordSeed);
        for (uint256 i; i < 4 && game.rngLocked(); i++) {
            _crank(false);
        }
        _noteOpenedDay();
        _checkSealedHeaders();
    }

    function _fulfilPending(uint256 wordSeed) internal {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;
        try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("craps-seal-word", wordSeed, reqId))) | 1) {
            ghost_fulfilments++;
        } catch {
            return;
        }
        if (!game.rngLocked() && game.isRngFulfilled()) {
            _crank(false);
        }
        // Property (3): the request that just landed must not have been the one in flight when
        // any armed field bound its index.
        uint256 n = armedSlots.length;
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[i];
            if (inFlightReqAtArm[slot] != reqId) continue;
            if (_lootboxRngWord(armedIndexOf[slot]) != 0) ghost_inFlightLandedOnArmedIndex++;
        }
        _countLandedWords();
    }

    /// @dev One keeper crank through the state engine. The engine settles read-bound Craps fields
    ///      in its own consumer order right after a word is published (6d0e64b09/60d31f775), so a
    ///      field can settle inside a crank rather than at the settle door: property (5) is
    ///      measured here too. A field settled in this crank had a real word if its leaf was worded
    ///      before the crank or the crank published that leaf's word.
    mapping(uint64 => bool) internal keeperSettledOnWord;

    function _crank(bool asActor) internal {
        if (measureTableSettlement) _settleReadCrapsMeasured();
        uint256 cursorBefore = _cursor();
        uint256 reqBefore = _unfulfilledRequestId();
        bool lockedBefore = game.rngLocked();
        bool midDayBefore = !lockedBefore && _requestActive();
        // A window armed outside any measured path (e.g. inside an entry) is recorded unmeasured
        // first, so the post-crank scan below only measures arms made by this crank.
        for (uint256 i; i < trackedSlots.length; i++) {
            uint64 shut = trackedSlots[i];
            uint48 rawShut = craps.slotIndexOf(shut);
            if (armedSeen[shut] || rawShut == 0) continue;
            _recordArm(shut, rawShut - 1, 0, 0, false, false, false);
        }
        uint256 n = armedSlots.length;
        uint256[] memory resolvedBefore = new uint256[](n);
        bool[] memory wordedBefore = new bool[](n);
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[i];
            resolvedBefore[i] = craps.battleOf(craps.keyOfSlot(slot)).resolved;
            wordedBefore[i] = _lootboxRngWord(armedIndexOf[slot]) != 0;
        }
        vm.recordLogs();
        if (asActor) vm.prank(currentActor);
        try game.mineFlip() {} catch {}
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[i];
            if (craps.battleOf(craps.keyOfSlot(slot)).resolved <= resolvedBefore[i]) continue;
            bool worded = wordedBefore[i];
            for (uint256 k; k < logs.length && !worded; k++) {
                if (logs[k].emitter != address(game) || logs[k].topics.length == 0
                    || logs[k].topics[0] != keccak256("LootboxRngApplied(uint48,uint256,uint256)")) continue;
                (uint48 index, uint256 word,) = abi.decode(logs[k].data, (uint48, uint256, uint256));
                if (index == armedIndexOf[slot] && word != 0) worded = true;
            }
            // One field counts once however many keeper chunks its seats take. Only the
            // non-vacuity count is taken here: a keeper crank also refunds lapsed or terminally
            // abandoned seats without any word, so property (5) stays measured at the settle door,
            // and the keeper's own zero-word refusal is LootboxCraps._wordAt / _keepRngCohort's.
            if (worded && !keeperSettledOnWord[slot]) {
                keeperSettledOnWord[slot] = true;
                ghost_settlesWithWord++;
            }
        }
        // The engine's scheduled maintenance arms closed windows inside the crank (it must finish
        // before the daily request, 6d0e64b09). Like keep()'s pre-scan for the advance chain's own
        // keeper hop, record those arms for the slip freeze and coverage only: the crank brackets
        // several actions, so its arm-time cursor is not observed. Properties (1)/(2) stay
        // measured on the handler's own arm paths.
        uint256 t = trackedSlots.length;
        for (uint256 i; i < t; i++) {
            uint64 slot = trackedSlots[i];
            if (armedSeen[slot]) continue;
            uint48 raw = craps.slotIndexOf(slot);
            if (raw == 0) continue;
            _recordArm(slot, raw - 1, cursorBefore, reqBefore, lockedBefore, midDayBefore, false);
        }
        _noteBoundDay();
    }

    /// @dev Keeper-door snapshot per armed field: seats resolved so far, and whether its leaf is
    ///      worded (stored, to keep the keeper path within the stack).
    uint256[] internal keepResolvedBefore;
    bool[] internal keepWordedBefore;

    function _armedSettleSnapshot() internal {
        delete keepResolvedBefore;
        delete keepWordedBefore;
        uint256 n = armedSlots.length;
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[i];
            keepResolvedBefore.push(craps.battleOf(craps.keyOfSlot(slot)).resolved);
            keepWordedBefore.push(_lootboxRngWord(armedIndexOf[slot]) != 0);
        }
    }

    /// @dev The table's own `keepScheduled` settles the read cohort's frontier fields at the Craps
    ///      read stage (the same walk the engine runs). Count a field it settled on a worded leaf
    ///      once, exactly as `_crank` does for the engine's own settlement (non-vacuity only).
    function _countWordedKeeperSettles() internal {
        uint256 n = keepResolvedBefore.length;
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[i];
            if (!keepWordedBefore[i] || keeperSettledOnWord[slot]) continue;
            if (craps.battleOf(craps.keyOfSlot(slot)).resolved <= keepResolvedBefore[i]) continue;
            keeperSettledOnWord[slot] = true;
            ghost_settlesWithWord++;
        }
    }

    /// @dev The engine opens a craps day inside the crank that applies its word. Remember the
    ///      earliest one, so the keeper bound spans every opened day's windows.
    function _noteBoundDay() internal {
        (uint24 od,) = craps.bonusDayOf();
        if (od != 0 && (boundFirstDay == 0 || od < boundFirstDay)) boundFirstDay = od;
    }

    /// @dev Under `measureTableSettlement`: step the engine through the delivered cohort's earlier
    ///      checkpoints with the smallest allowance each admits (one mineFlip composes every
    ///      checkpoint its allowance admits, 60d31f775), and settle its Craps read stage (stage 6)
    ///      through the measured keeper door, `keepScheduled`, which runs the same read-cohort walk.
    function _settleReadCrapsMeasured() internal {
        for (uint256 i; i < 96; i++) {
            if (game.rngConsumerStage() == 6) {
                if (!_keep(0)) return;
                continue;
            }
            uint8 next = game.nextMinerAction();
            // Publish (3) through Decimator (12): the delivered cohort's work before its Craps stage.
            if (next < 3 || next > 12) return;
            if (!_minimalEngineStep()) return;
        }
    }

    /// @dev One mineFlip at the smallest allowance (250k steps up to the 16.7M ceiling) that makes
    ///      progress, so the engine stops at the next checkpoint it cannot admit.
    function _minimalEngineStep() internal returns (bool ok) {
        for (uint256 g = 1_000_000; g <= 16_750_000; g += 250_000) {
            (ok, ) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip()"));
            if (ok) return true;
        }
    }

    /// @notice Open the DAILY VRF window and leave it open: warp to the next day and fire the
    ///         heartbeat, stopping the moment the daily request latches `rngLocked()`. Craps doors
    ///         called after this run inside the daily window until `fulfil` / `advanceDay` close it.
    function openDailyWindow(uint256 actorSeed) external useActor(actorSeed) {
        _openDailyWindow();
    }

    function _openDailyWindow() internal returns (bool open) {
        if (game.gameOver()) return false;
        if (game.rngLocked()) return true;
        _finishHumanRead();
        vm.warp(_dayStart() + 1 days + 5 minutes);
        _buyTicket();
        // The engine prepares the day (subscriptions, scheduled Craps maintenance) one checkpoint
        // per call before its daily request (60d31f775).
        for (uint256 i; i < 64 && !game.rngLocked(); i++) {
            _crank(true);
        }
        return game.rngLocked();
    }

    /// @dev Diagnostic read for the focused pins: the slot primeLockedArm would shut right now.
    function armTargetFor(uint256 seed) external view returns (uint64) {
        return _armTarget(seed);
    }

    /// @notice SELF-PRIMING: shut a field while the DAILY window is held. Seats one entrant on
    ///         today's opener if no shut-able field exists, opens the next day's window (so that
    ///         field is now yesterday's and closed), and arms it under the lock — the permissionless
    ///         arm is good for any past window, and its own request is refused while the lock holds.
    function primeLockedArm(uint256 actorSeed, uint256 boardSeed) external useActor(actorSeed) {
        if (game.gameOver()) return;
        if (!game.rngLocked()) {
            if (_armTarget(actorSeed) == 0) {
                // The daily request now waits for scheduled Craps maintenance, which arms every
                // closed scheduled window first (6d0e64b09), so no scheduled window is left to shut
                // under the lock. A custom battle is outside the schedule: open one whose close
                // falls before the next day's request, so it is closed and unarmed under the lock.
                _createCustom(actorSeed, boardSeed);
            }
            if (!_openDailyWindow()) return;
        }
        uint64 slot = _armTarget(actorSeed);
        if (slot == 0) return;
        if (slot >= CUSTOM_SLOT_BASE) {
            uint256 closeTime = customCloseOf[slot];
            if (closeTime == 0 || block.timestamp < closeTime) return;
        } else if (slot / SLOTS_PER_DAY >= craps.currentDayIndex()) {
            return; // only a PAST day's window is closed under a fresh lock
        }
        _armAndMeasure(slot);
    }

    /// @notice SELF-PRIMING: two fields shut back to back, so the second arm runs while the first
    ///         arm's own lootbox request is in flight (the mid-day window shape).
    function primeInFlightArms(uint256 actorSeed, uint256 boardSeed) external useActor(actorSeed) {
        _primeInFlightArms(actorSeed, boardSeed);
    }

    function _primeInFlightArms(uint256 actorSeed, uint256 boardSeed) internal {
        if (game.gameOver()) return;
        if (game.rngLocked() || _requestActive()) {
            // Some window is already open: a single arm now is the measurement.
            uint64 s0 = _armTarget(actorSeed);
            if (s0 == 0) return;
            if (s0 < CUSTOM_SLOT_BASE) {
                uint24 d0 = uint24(s0 / SLOTS_PER_DAY);
                if (d0 > craps.currentDayIndex()) return;
                if (d0 == craps.currentDayIndex()) {
                    uint256 close0 = _closeOf((s0 % SLOTS_PER_DAY) - 1);
                    if (block.timestamp - _dayStart() < close0) vm.warp(_dayStart() + close0);
                }
            } else if (customCloseOf[s0] == 0 || block.timestamp < customCloseOf[s0]) {
                return;
            }
            _armAndMeasure(s0);
            return;
        }
        if (!_crapsDayOpen() && !_driveDay(actorSeed)) return;
        uint24 d = craps.currentDayIndex();
        uint256 elapsed = block.timestamp - _dayStart();
        // The two earliest periods still taking bets and not yet shut.
        uint256 pa = PERIODS;
        uint256 pb = PERIODS;
        for (uint256 i; i < PERIODS; i++) {
            if (elapsed >= _closeOf(i) || craps.slotIndexOf(_windowSlot(d, i)) != 0) continue;
            if (pa == PERIODS) pa = i;
            else {
                pb = i;
                break;
            }
        }
        if (pb == PERIODS) {
            // Not enough of today left: roll to a fresh day and take its first two.
            if (!_driveDay(actorSeed + 1)) return;
            d = craps.currentDayIndex();
            pa = 0;
            pb = 1;
        }
        address a = actors[actorSeed % actors.length];
        address b = actors[(actorSeed + 1) % actors.length];
        if (craps.daySeatNumberOf(d, a) != 0 || craps.daySeatNumberOf(d, b) != 0) return;
        _fund(a);
        _fund(b);
        uint256 flipA = coin.balanceOf(a);
        uint256 flipB = coin.balanceOf(b);
        vm.prank(a);
        try craps.enterBonusBattle(pa, _board(boardSeed), 1) returns (uint256 betId) {
            _trackBet(betId);
            ghost_entries++;
        } catch {
            return;
        }
        ghost_flipBurnedIn += flipA - coin.balanceOf(a);
        vm.prank(b);
        try craps.enterBonusBattle(pb, _board(boardSeed + 1), 1) returns (uint256 betId) {
            _trackBet(betId);
            ghost_entries++;
        } catch {
            return;
        }
        ghost_flipBurnedIn += flipB - coin.balanceOf(b);
        vm.warp(_dayStart() + _closeOf(pb));
        _armAndMeasure(_windowSlot(d, pa));
        _sealRequest(); // the shut makes no request; an ordinary one seals its buffer
        if (!_requestActive()) return; // the request was refused; nothing in flight
        _armAndMeasure(_windowSlot(d, pb));
    }

    // =========================================================================
    // Craps doors — every one isolation-checked against the game's consumed set
    // =========================================================================

    /// @notice Enter one of today's still-open bonus windows on the REAL table (FLIP burned through
    ///         the real gate).
    function enterWindow(uint256 actorSeed, uint256 boardSeed, uint256 periodSeed, bool high)
        external
        useActor(actorSeed)
    {
        if (!_crapsDayOpen()) return;
        uint24 d = craps.currentDayIndex();
        uint256 elapsed = block.timestamp - _dayStart();
        uint256 p = periodSeed % PERIODS;
        bool found;
        for (uint256 i; i < PERIODS; i++) {
            uint256 cand = (p + i) % PERIODS;
            if (elapsed < _closeOf(cand) && craps.slotIndexOf(_windowSlot(d, cand)) == 0) {
                p = cand;
                found = true;
                break;
            }
        }
        if (!found) return;
        if (craps.daySeatNumberOf(d, currentActor) != 0) return;
        uint16 mult = 1;
        if (high) {
            uint256 h = craps.highMultForDay(d);
            if (h < 2) return;
            mult = uint16(h);
        }
        _fund(currentActor);
        uint256 flip0 = coin.balanceOf(currentActor);
        (bool open, bool midDay, bytes32 h0) = _before();
        vm.prank(currentActor);
        try craps.enterBonusBattle(p, _board(boardSeed), mult) returns (uint256 betId) {
            _trackBet(betId);
            ghost_entries++;
        } catch {}
        _after(open, midDay, h0);
        ghost_flipBurnedIn += flip0 - coin.balanceOf(currentActor);
    }

    /// @notice Take the whole day through the day lane while its first window still sells it.
    function enterDay(uint256 actorSeed, uint256 boardSeed, bool high) external useActor(actorSeed) {
        if (!_crapsDayOpen()) return;
        uint24 d = craps.currentDayIndex();
        (, uint256 period,) = craps.currentBonusSlot();
        if (period != 0) return;
        if (craps.daySeatNumberOf(d, currentActor) != 0) return;
        uint16 mult = 1;
        if (high) {
            uint256 h = craps.highMultForDay(d);
            if (h < 2) return;
            mult = uint16(h);
        }
        _fund(currentActor);
        uint256 flip0 = coin.balanceOf(currentActor);
        (bool open, bool midDay, bytes32 h0) = _before();
        vm.prank(currentActor);
        try craps.enterBonusDay(_board(boardSeed), mult) returns (uint256) {
            ghost_entries++;
            ghost_dayTickets++;
        } catch {}
        _after(open, midDay, h0);
        ghost_flipBurnedIn += flip0 - coin.balanceOf(currentActor);
    }

    /// @notice Re-spread a tracked slip. Before its field shuts this is the holder's right; after,
    ///         the door must refuse — property (4) measures the stored slip either way.
    function amend(uint256 pickSeed, uint256 boardSeed) external {
        if (betIds.length == 0) return;
        uint256 betId = betIds[pickSeed % betIds.length];
        // Half the time, aim at a slip whose field has already shut — the attempt the frozen-slip
        // property exists for — so every run tries it.
        if (pickSeed & 1 == 0) {
            for (uint256 i; i < armedSlots.length; i++) {
                uint256[] storage ids = slotBets[armedSlots[(pickSeed >> 1) % armedSlots.length]];
                if (ids.length != 0) {
                    betId = ids[(pickSeed >> 2) % ids.length];
                    break;
                }
            }
        }
        CrapsBattle.Bet memory b = craps.betOf(betId);
        if (b.player == address(0)) return;
        uint64 slot = uint64(betId >> 64);
        bool armed = craps.slotIndexOf(slot) != 0;
        if (armed) ghost_postArmAmendAttempts++;
        // A jackpot slot is locked by the daily request rather than by this handler's arm, so it
        // has no recorded seal: measure it against the slip as it stood before the attempt.
        bytes32 sealed_ = sealedHeader[betId] != 0 ? sealedHeader[betId] : _headerOf(betId);
        (bool open, bool midDay, bytes32 h0) = _before();
        vm.prank(b.player);
        try craps.amendSlip(betId, _board(boardSeed)) {
            if (armed) ghost_postArmAmendsAccepted++;
        } catch {}
        _after(open, midDay, h0);
        if (armed && _headerOf(betId) != sealed_) ghost_postArmSlipMutations++;
    }

    /// @notice Shut a window that has stopped taking bets (permissionless door). Properties (1)
    ///         and (2) are measured here against the cursor and the word leaf the field binds to.
    function arm(uint256 pickSeed) external useActor(pickSeed) {
        uint64 slot = _armTarget(pickSeed);
        if (slot == 0) return;
        if (slot < CUSTOM_SLOT_BASE) {
            // Today's window: move to its close (same day, so no heartbeat is skipped).
            uint24 d = uint24(slot / SLOTS_PER_DAY);
            if (d == craps.currentDayIndex()) {
                uint256 close = _closeOf((slot % SLOTS_PER_DAY) - 1);
                if (block.timestamp - _dayStart() < close) vm.warp(_dayStart() + close);
            }
        } else {
            uint256 closeTime = customCloseOf[slot];
            if (closeTime == 0) return;
            if (block.timestamp < closeTime) vm.warp(closeTime);
        }
        _armAndMeasure(slot);
        // Most shuts are followed by an ordinary request that seals the window; the rest are left
        // for the fuzzer's own sealRequest / keeper / daily-advance sequencing.
        if (pickSeed % 4 != 0) _sealRequest();
    }

    /// @notice An ordinary mid-day request from a non-craps caller: with a craps window pending on
    ///         the write buffer it seals that buffer and its word settles the window.
    function sealRequest(uint256 seed) external {
        _sealRequest();
    }

    function _sealRequest() internal returns (bool ok) {
        if (game.gameOver()) return false;
        _finishHumanRead();
        ok = _tryRequest();
        if (ok) return true;
        // The read cohort may still owe the craps lane: drain it, then ask again.
        if (_drainReadCrapsCohort()) ok = _tryRequest();
    }

    function _tryRequest() internal returns (bool ok) {
        uint256 packed = uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT)));
        bool pending = packed & (uint256(1) << (250 + _cursor())) != 0;
        vm.prank(address(uint160(0x5ea1)));
        try game.requestLootboxRng() {
            ok = true;
            if (pending) ghost_sealRequests++;
        } catch {}
    }

    function _drainReadCrapsCohort() internal returns (bool drained) {
        uint48 read = RecyclingState.readBuffer(address(game));
        if (RecyclingState.word(address(game), read) == 0) return false;
        uint256 flag = uint256(1) << (250 + read);
        for (uint256 i; i < 64; i++) {
            if (uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) & flag == 0) return drained;
            try JackpotBattle(address(craps)).keepRngCohort(read, 1_888) {
                drained = true;
            } catch {
                return drained;
            }
        }
    }

    function _armAndMeasure(uint64 slot) internal {
        uint256 cursorBefore = _cursor();
        uint256 reqBefore = _unfulfilledRequestId();
        (bool open, bool midDay, bytes32 h0) = _before();
        uint48 index;
        bool ok;
        vm.prank(currentActor);
        if (slot < CUSTOM_SLOT_BASE) {
            try craps.armWindow(slot) returns (uint48 idx) {
                index = idx;
                ok = true;
            } catch {}
        } else {
            try craps.closeBattle(slot) returns (uint48 idx) {
                index = idx;
                ok = true;
            } catch {}
        }
        _after(open, midDay, h0);
        if (!ok) return;
        _recordArm(slot, index, cursorBefore, reqBefore, open, midDay);
    }

    function _recordArm(uint64 slot, uint48 index, uint256 cursorBefore, uint256 reqBefore, bool open, bool midDay)
        internal
    {
        _recordArm(slot, index, cursorBefore, reqBefore, open, midDay, true);
    }

    /// @dev `measured` is false for a window found already shut by a path the handler did not
    ///      bracket (the advance chain's own keeper hop): its arm-time cursor and word state are
    ///      unknown, and a seal request may have moved both since, so only the freeze is recorded.
    function _recordArm(
        uint64 slot,
        uint48 index,
        uint256 cursorBefore,
        uint256 reqBefore,
        bool open,
        bool midDay,
        bool measured
    ) internal {
        ghost_arms++;
        if (open) ghost_armsWhileDailyLocked++;
        if (midDay) ghost_armsWhileMidDayInFlight++;
        if (measured) {
            // Property (1): the bound leaf holds no word.
            if (_lootboxRngWord(index) != 0) ghost_armsOnWordedIndex++;
            // Property (2): the bound leaf is the write buffer at the arm — never a leaf a request
            // has already claimed (the in-flight leaf is the other buffer).
            if (uint256(index) != cursorBefore) ghost_armsBelowCursor++;
        }
        if (!armedSeen[slot]) {
            armedSeen[slot] = true;
            armedSlots.push(slot);
        }
        armedIndexOf[slot] = index;
        inFlightReqAtArm[slot] = reqBefore;
        // Freeze the slips that just bound.
        uint256[] storage ids = slotBets[slot];
        for (uint256 i; i < ids.length; i++) {
            sealedHeader[ids[i]] = _headerOf(ids[i]);
        }
    }

    /// @notice A custom battle (creator-opened, joinable regardless of the day clock — the one
    ///         door that takes money while the daily lock is held). Actors enter it at once.
    function createCustom(uint256 seed, uint256 boardSeed) external {
        _createCustom(seed, boardSeed);
    }

    function _createCustom(uint256 seed, uint256 boardSeed) internal {
        if (game.gameOver()) return;
        uint40 closeTime = uint40(block.timestamp + 10 minutes + (seed % 30 minutes));
        // Read the goal floor BEFORE the prank: an argument's external call would consume it and
        // leave the handler itself as the (unauthorized) creator.
        uint16 goalMult = uint16(craps.MIN_BATTLE_GOAL_MULT());
        vm.prank(ContractAddresses.CREATOR);
        uint64 slot;
        try craps.createBattle(600, 10, goalMult, 0, closeTime, true, 0) returns (
            uint64 s
        ) {
            slot = s;
        } catch {
            return;
        }
        ghost_customBattles++;
        customCloseOf[slot] = closeTime;
        uint256 n = 1 + (seed % actors.length);
        for (uint256 i; i < n; i++) {
            address who = actors[(seed + i) % actors.length];
            _fund(who);
            uint256 flip0 = coin.balanceOf(who);
            (bool open, bool midDay, bytes32 h0) = _before();
            vm.prank(who);
            try craps.enterBattle(slot, _board(boardSeed + i), 1) returns (uint256 betId) {
                _trackBet(betId);
                ghost_entries++;
            } catch {}
            _after(open, midDay, h0);
            ghost_flipBurnedIn += flip0 - coin.balanceOf(who);
        }
    }

    /// @notice Settle a shut field. Property (5): the resolution cursor may only advance on a
    ///         real word. SELF-PRIMING for the worded case: if no shut field holds a word yet, the
    ///         exempt machinery is driven (a pending fulfilment, else a day rollover, whose daily
    ///         request lands the last-bound leaf) before the settle is measured; a field with no
    ///         word is still tried when that fails, which exercises the zero-word refusal.
    function settle(uint256 pickSeed) external useActor(pickSeed) {
        uint64 slot = _wordedSettleTarget(pickSeed);
        if (slot == 0) {
            _fulfilPending(pickSeed);
            // Let an open daily window finish: its word seals whatever window waits on the buffer.
            for (uint256 i; i < 8 && game.rngLocked(); i++) {
                _crank(false);
                _fulfilPending(pickSeed + 4 + i);
            }
            slot = _wordedSettleTarget(pickSeed);
            if (slot == 0 && _settleTargetAny(pickSeed) == 0) {
                // Nothing shut yet: build a field, shut it, and let the next request land its word.
                _primeInFlightArms(pickSeed, pickSeed >> 8);
                _fulfilPending(pickSeed + 1);
            }
            if (slot == 0 && _settleTargetAny(pickSeed) != 0) {
                // A shut window waits for the next request to seal it: land what is in flight,
                // send an ordinary one, and land that.
                _fulfilPending(pickSeed + 2);
                for (uint256 i; i < 8 && game.rngLocked(); i++) {
                    _crank(false);
                    _fulfilPending(pickSeed + 4 + i);
                }
                slot = _wordedSettleTarget(pickSeed);
                if (slot == 0) {
                    _sealRequest();
                    _fulfilPending(pickSeed + 3);
                    slot = _wordedSettleTarget(pickSeed);
                }
            }
            if (slot == 0 && _settleTargetAny(pickSeed) != 0) {
                _driveDay(pickSeed);
                slot = _wordedSettleTarget(pickSeed);
            }
            if (slot == 0) slot = _settleTargetAny(pickSeed);
            if (slot == 0) return;
        }
        uint48 index = armedIndexOf[slot];
        bool hasWord = _lootboxRngWord(index) != 0;
        CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
        if (!hasWord) ghost_settleAttemptsWithoutWord++;
        uint256 stake0 = _stakeLedger();
        uint256 bound = _liabilityBound(slot);
        (bool open, bool midDay, bytes32 h0) = _before();
        vm.prank(currentActor);
        // `slot` may be a scheduled window's or a custom battle's — `armedSlots` tracks both —
        // so this settles through the unrestricted test door rather than the production
        // `resolveSlot`, which now rejects a scheduled slot outright.
        try craps.settleSlot(slot, type(uint64).max) {} catch {}
        _after(open, midDay, h0);
        uint256 credited = _stakeLedger() - stake0;
        ghost_creditedOut += credited;
        if (credited > bound) {
            ghost_creditsOverBound++;
            (ghost_lastOverCredited, ghost_lastOverBound, ghost_lastOverSlot, ghost_lastOverWasKeep) =
                (credited, bound, slot, false);
        }
        CrapsBattle.Battle memory after_ = craps.battleOf(craps.keyOfSlot(slot));
        if (after_.resolved > b.resolved) {
            if (hasWord) ghost_settlesWithWord++;
            else ghost_settlesWithoutWord++;
        }
        _checkSealedHeaders();
    }

    /// @dev A shut field whose word has landed and whose scoreboard still owes seats.
    function _wordedSettleTarget(uint256 pickSeed) internal view returns (uint64) {
        uint256 n = armedSlots.length;
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[(pickSeed + i) % n];
            if (_lootboxRngWord(armedIndexOf[slot]) == 0) continue;
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
            if (b.entrants == 0 || b.resolved == b.entrants) continue;
            return slot;
        }
        return 0;
    }

    /// @dev Any shut field whose scoreboard still owes seats, worded or not.
    function _settleTargetAny(uint256 pickSeed) internal view returns (uint64) {
        uint256 n = armedSlots.length;
        for (uint256 i; i < n; i++) {
            uint64 slot = armedSlots[(pickSeed + i) % n];
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
            if (b.entrants == 0 || b.resolved == b.entrants) continue;
            return slot;
        }
        return 0;
    }

    /// @notice One keeper crank at a random budget: the scheduled cursor's own arm path. Any field
    ///         it shuts is measured exactly like a permissionless arm.
    function keep(uint64 budget) external useActor(budget) {
        _noteOpenedDay();
        _keep(budget);
    }

    /// @dev The measured keeper crank. Does not touch the opened-day labels (first/lastOpenedDay),
    ///      which drive the subsidy ghosts; the bound reads its own range.
    function _keep(uint64 budget) internal returns (bool progressed) {
        uint256 cursorBefore = _cursor();
        uint256 reqBefore = _unfulfilledRequestId();
        _noteBoundDay();
        uint256 stake0 = _stakeLedger();
        uint256 bound = _keeperBound();
        (bool open, bool midDay, bytes32 h0) = _before();
        for (uint256 i; i < trackedSlots.length; i++) {
            uint64 shut = trackedSlots[i];
            uint48 rawShut = craps.slotIndexOf(shut);
            if (armedSeen[shut] || rawShut == 0) continue;
            _recordArm(shut, rawShut - 1, 0, 0, false, false, false);
        }
        progressed = _keepScheduledCounted(budget);
        _after(open, midDay, h0);
        _checkKeeperCredit(stake0, bound);
        // Anything newly armed among the tracked windows was armed by this crank.
        uint256 n = trackedSlots.length;
        for (uint256 i; i < n; i++) {
            uint64 slot = trackedSlots[i];
            if (armedSeen[slot]) continue;
            uint48 raw = craps.slotIndexOf(slot);
            if (raw == 0) continue;
            _recordArm(slot, raw - 1, cursorBefore, reqBefore, open, midDay);
        }
        _checkSealedHeaders();
    }

    /// @dev The table's own keeper door, with the fields it settles on worded leaves counted.
    function _keepScheduledCounted(uint64 budget) internal returns (bool progressed) {
        _armedSettleSnapshot();
        progressed = _callKeepScheduled(budget);
        _countWordedKeeperSettles();
    }

    function _callKeepScheduled(uint64 budget) internal returns (bool progressed) {
        vm.prank(currentActor);
        try craps.keepScheduled(budget % 64) returns (bool moved, uint64) {
            ghost_keeps++;
            progressed = moved;
        } catch {
            ghost_keepReverts++;
        }
    }

    function _checkKeeperCredit(uint256 stake0, uint256 bound) internal {
        uint256 credited = _stakeLedger() - stake0;
        ghost_creditedOut += credited;
        if (credited > bound) {
            ghost_creditsOverBound++;
            (ghost_lastOverCredited, ghost_lastOverBound, ghost_lastOverSlot, ghost_lastOverWasKeep) =
                (credited, bound, 0, true);
        }
    }

    /// @notice The vault comps banked craps passes through the REAL vault and the REAL FLIP
    ///         comp lane (its owner is the deployer, who holds the DGVE majority). A grant must
    ///         charge the lane exactly the passes it banked times their value, an over-ask must be
    ///         refused whole, and nothing but a grant may ever lower the lane.
    ///         Seven requests in eight ask for one to eight passes a recipient, which the 200-pass
    ///         lane can serve many times over; the rest keep the raw draw, so over-asks are still
    ///         exercised. Two entry points share the body so a run lands a grant reliably: the
    ///         suite's per-run vacuity guard needs at least one, and a raw 0..255 ask was refused
    ///         often enough that a whole run could see none.
    function grantComps(uint256 seed, uint8 countEach) external {
        _grantComps(seed, countEach);
    }

    /// @notice A second door into the same grant, doubling how often the fuzzer draws it.
    function grantCompsAgain(uint256 seed, uint8 countEach) external {
        _grantComps(seed, countEach);
    }

    function _grantComps(uint256 seed, uint8 countEach) internal {
        if (countEach < 224) countEach = 1 + (countEach % 8);
        uint256 n = 1 + (seed % 3);
        uint256[] memory reqs = new uint256[](n);
        uint256[] memory before = new uint256[](n);
        for (uint256 i; i < n; i++) {
            address to = actors[(seed + i) % actors.length];
            reqs[i] = uint256(uint160(to)) | (4 << 160) | (uint256(countEach) << 200);
            (before[i],) = craps.passCreditsOf(to);
        }
        uint256 laneBefore = coin.crapsCompAllowance();
        uint256 value = craps.NORMAL_PASS_VALUE();
        vm.prank(ContractAddresses.CREATOR);
        try vault.crapsComp(reqs) {
            uint256 banked;
            for (uint256 i; i < n; i++) {
                (uint256 now_,) = craps.passCreditsOf(address(uint160(reqs[i])));
                if (_distinct(reqs)) banked += now_ - before[i];
            }
            uint256 spent = laneBefore - coin.crapsCompAllowance();
            ghost_compsGranted += banked;
            ghost_compLaneSpent += spent;
            // Distinct recipients bank exactly what the lane was charged for; a repeated
            // recipient's before/after spans both grants, so only the charge is checked.
            if (_distinct(reqs) && spent != banked * value) ghost_compGrantsRefused = type(uint256).max;
            if (spent > laneBefore) ghost_compGrantsRefused = type(uint256).max;
        } catch {
            ghost_compGrantsRefused++;
            if (coin.crapsCompAllowance() != laneBefore) ghost_compGrantsRefused = type(uint256).max;
            // Within the lane, distinct recipients with room must be served.
            if (
                _distinct(reqs) && uint256(countEach) * n * value <= laneBefore
                    && _allHaveRoom(reqs, countEach)
            ) ghost_compGrantsRefused = type(uint256).max;
        }
    }

    function _allHaveRoom(uint256[] memory r, uint8 countEach) internal view returns (bool) {
        for (uint256 i; i < r.length; i++) {
            (uint256 have,) = craps.passCreditsOf(address(uint160(r[i])));
            if (have + countEach > type(uint32).max) return false;
        }
        return true;
    }

    function _distinct(uint256[] memory r) internal pure returns (bool) {
        for (uint256 i; i < r.length; i++) {
            for (uint256 j = i + 1; j < r.length; j++) {
                if (address(uint160(r[i])) == address(uint160(r[j]))) return false;
            }
        }
        return true;
    }

    /// @dev Everything a settlement of `slot` may credit: every seat's own engine-priced return
    ///      (the run with its boon, scaled for a high seat, plus a sole rider's ride — the day
    ///      tickets and the two protocol bodies priced the same way); the field's pooled stake;
    ///      the window's boost ceilings (the pot and the contested / sole-rider lanes); and the
    ///      whole progressive balance. A payout that draws from anything else is the divergence
    ///      this bounds.
    function _liabilityBound(uint64 slot) internal view returns (uint256 bound) {
        CrapsBattle.Battle memory bt = craps.battleOf(craps.keyOfSlot(slot));
        // Every seat the walk will settle, priced by the settlement engine itself through
        // `settlementOn`: the field's own seats `1..ownN` at the slot, then the day tickets under
        // the day slot (the protocol's two bodies among them). A run is NOT bounded by its goal —
        // the engine latches the goal as a reserve and keeps playing, escalating every few
        // shooters, so a hot hand returns a hundred bankrolls and a sole high rider rides it at
        // `2 * highMult - 1` copies. Only the engine's own figure is a bound on that. A seat the
        // engine cannot price yet (no word) is a seat the walk cannot settle yet either.
        (uint256 dayBase, uint64 dayN) = craps.dayFieldOf(slot);
        uint256 ownN = bt.entrants > dayN ? bt.entrants - dayN : 0;
        for (uint256 n = 1; n <= ownN; n++) {
            try craps.settlementOn((uint256(slot) << 64) | n, slot) returns (uint256 paid) {
                bound += paid;
            } catch {}
        }
        for (uint256 n = 1; n <= dayN; n++) {
            try craps.settlementOn(dayBase | n, slot) returns (uint256 paid) {
                bound += paid;
            } catch {}
        }
        if (slot < CUSTOM_SLOT_BASE) {
            uint24 day = uint24(slot / SLOTS_PER_DAY);
            // The day's word may already be retired from the two-day ring (c729ecfc9); the window's
            // own frozen terms still carry its high multiple.
            uint256 hm = craps.highMultForDay(day);
            uint256 frozenHm = craps.highMultOfSlot(slot);
            if (frozenHm > hm) hm = frozenHm;
            if (hm == 0) hm = 1;
            // The pot's boost is the window's advertised base times a rung of 1 / 4 / 40 / 400
            // over four — at most a hundred times the base — and the contested lane's boost is
            // drawn the same way off the high base. The table quotes that ceiling itself as
            // `_boostBase(w) * _BOOST_MAX_MULT`; a day's running budget is only the MEAN of it.
            // Ten granules of slack cover the nearest-ten rounding of each figure.
            bound += (craps.boostBaseOf(slot) + craps.highBaseOf(slot)) * 100 + 10 * 100 ether;
            // A contested lane pays its winner the other high seats' pooled principal, (hm - 1)
            // stakes per seat, which no seat's own preview contains.
            bound += bt.battleStake * (bt.entrants == 0 ? 1 : bt.entrants) * (hm - 1);
        } else {
            // A custom high lane pools its principal the same way as a scheduled one.
            uint256 hmc = craps.highMultOfSlot(slot);
            if (hmc > 1) bound += bt.battleStake * (bt.entrants == 0 ? 1 : bt.entrants) * (hmc - 1);
        }
        bound += bt.battleStake * (bt.entrants == 0 ? 1 : bt.entrants);
        bound += craps.progressiveOf();
        // A scheduled field whose winning run sets the biggest-dice-run record is credited a
        // share of the coinflip's record pool in the same call (at most the ceiling share, so
        // the whole pool bounds it).
        bound += coinflip.recordPool();
    }

    /// @dev The bound over every shut, worded field a keeper crank may settle: each opened day's
    ///      seven windows plus every tracked custom battle.
    function _keeperBound() internal view returns (uint256 bound) {
        uint24 today = craps.currentDayIndex();
        // Every day from the earliest one seen open (by the handler's own drive or by any engine
        // crank) through today: the engine opens days inside cranks the handler does not label.
        uint24 from = firstOpenedDay;
        if (boundFirstDay != 0 && (from == 0 || boundFirstDay < from)) from = boundFirstDay;
        uint24 to = lastOpenedDay > today ? lastOpenedDay : today;
        for (uint24 d = from; d != 0 && d <= to; d++) bound += _dayKeeperBound(d, today);
        for (uint256 i; i < armedSlots.length; i++) {
            uint64 slot = armedSlots[i];
            if (slot < CUSTOM_SLOT_BASE) continue;
            if (_lootboxRngWord(armedIndexOf[slot]) != 0) bound += _liabilityBound(slot);
        }
    }

    /// @dev One day's seven windows in the keeper bound (see `_keeperBound`).
    function _dayKeeperBound(uint24 d, uint24 today) internal view returns (uint256 bound) {
        uint256 hm = craps.highMultForDay(d);
        if (hm == 0) hm = 1;
        for (uint256 p; p < PERIODS; p++) {
            uint64 slot = _windowSlot(d, p);
            uint48 raw = craps.slotIndexOf(slot);
            if (raw == 0) {
                // A window of a PAST day that never shut lapses: the keeper's sweep refunds
                // every seat's stake (window entrants, day tickets, the two protocol seats).
                if (d < today) bound += _lapseBound(d, p, slot, hm);
                continue;
            }
            if (_lootboxRngWord(raw - 1) == 0) continue;
            bound += _liabilityBound(slot);
        }
    }

    /// @dev A lapsed window's refund ceiling. Its terms read the day's word, which the two-day ring
    ///      retires (c729ecfc9): a window whose terms are gone contributes nothing here.
    function _lapseBound(uint24 d, uint256 p, uint64 slot, uint256 hm) internal view returns (uint256) {
        try craps.bonusTermsFor(d, p) returns (uint128 bankroll, uint128, uint256, uint256 bounty, uint256, uint256) {
            try craps.keyOfSlot(slot) returns (bytes32 key) {
                uint256 seats = craps.battleOf(key).entrants + craps.dayTicketsOf(d) + 2;
                return seats * (uint256(bankroll) + bounty) * hm;
            } catch {}
        } catch {}
        return 0;
    }

    /// @dev Every recipient's coinflip stake — the table's payout lane — in one sum.
    function _stakeLedger() internal view returns (uint256 total) {
        for (uint256 i; i < actors.length; i++) {
            total += coinflip.coinflipAmount(actors[i]);
        }
        total += coinflip.coinflipAmount(ContractAddresses.SDGNRS) + coinflip.coinflipAmount(ContractAddresses.VAULT)
            + coinflip.coinflipAmount(ContractAddresses.CREATOR);
    }

    // =========================================================================
    // Falsifiability seam (test-only; excluded from the campaign)
    // =========================================================================

    /// @notice Inject a deliberately invalid arm observation into the real ghost oracle.
    ///         The snapshot makes the fault injection counter-neutral and never changes a battle.
    function debugSeedWordedArmAndCheck(uint64 slot) external returns (bool detected) {
        uint256 snapshot = vm.snapshotState();
        uint48 target = uint48(_cursor() ^ 1);
        RecyclingState.seedWord(address(game), target, bytes32(uint256(keccak256("craps-seal-falsify")) | 1));
        uint256 beforeCount = ghost_armsOnWordedIndex;
        _recordArm(slot, target, _cursor(), 0, false, false);
        detected = ghost_armsOnWordedIndex == beforeCount + 1;
        vm.revertToStateAndDelete(snapshot);
    }

    // =========================================================================
    // Internals
    // =========================================================================

    function _armTarget(uint256 pickSeed) internal view returns (uint64) {
        uint256 n = trackedSlots.length;
        if (n == 0) return 0;
        uint24 today = craps.currentDayIndex();
        for (uint256 i; i < n; i++) {
            uint64 slot = trackedSlots[(pickSeed + i) % n];
            if (craps.slotIndexOf(slot) != 0) continue;
            if (slot < CUSTOM_SLOT_BASE) {
                // A past day's window, or one of today's: both are armable once closed.
                if (slot / SLOTS_PER_DAY > today) continue;
            }
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
            if (b.entrants == 0) continue;
            return slot;
        }
        return 0;
    }

    function _trackBet(uint256 betId) internal {
        betIds.push(betId);
        uint64 slot = uint64(betId >> 64);
        slotBets[slot].push(betId);
        if (!slotSeen[slot]) {
            slotSeen[slot] = true;
            trackedSlots.push(slot);
        }
    }

    /// @dev The frozen slip fields: owner, slot, seat, the packed board, the standing. The
    ///      `settled` / `battleClaimed` flags are the settlement's own writes and are excluded.
    function _headerOf(uint256 betId) internal view returns (bytes32) {
        CrapsBattle.Bet memory b = craps.betOf(betId);
        return keccak256(abi.encode(b.player, b.slot, b.seat, b.chips));
    }

    function _checkSealedHeaders() internal {
        uint256 n = armedSlots.length;
        for (uint256 i; i < n; i++) {
            uint256[] storage ids = slotBets[armedSlots[i]];
            for (uint256 j; j < ids.length; j++) {
                if (_headerOf(ids[j]) != sealedHeader[ids[j]]) ghost_postArmSlipMutations++;
            }
        }
    }

    function _countLandedWords() internal {
        uint256 n = armedSlots.length;
        uint256 landed;
        for (uint256 i; i < n; i++) {
            if (_lootboxRngWord(armedIndexOf[armedSlots[i]]) != 0) landed++;
        }
        if (landed > ghost_wordsLandedOnArmedIndices) ghost_wordsLandedOnArmedIndices = landed;
    }

    function _crapsDayOpen() internal view returns (bool) {
        (uint24 opened,) = craps.bonusDayOf();
        return opened == craps.currentDayIndex() && craps.dailyWordAt(opened) != 0;
    }

    function _fund(address who) internal {
        if (coin.balanceOf(who) >= FLIP_FLOOR) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, FLIP_TOP_UP);
    }

    function _buyTicket() internal {
        (,,,, uint256 priceWei) = game.purchaseInfo();
        if (priceWei == 0 || priceWei > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchase{value: priceWei}(currentActor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {}
            catch {}
    }

    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 1 == PERIODS) return 1 days - craps.EVENT_LEAD();
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    function _windowSlot(uint24 day, uint256 period) internal pure returns (uint64) {
        return uint64(uint256(day) * SLOTS_PER_DAY + period + 1);
    }

    function _board(uint256 seed) internal pure returns (Craps.Bets memory b) {
        uint24 count = uint24(seed % 8);
        uint24 first = count > 3 ? 3 : count;
        uint24 rest = count - first;
        uint24 second = rest > 3 ? 3 : rest;
        uint24 third = rest - second;
        uint256 shape = (seed >> 3) % 4;
        if (shape == 0) {
            b.place4 = first;
            b.place10 = second;
            b.place5 = third;
        } else if (shape == 1) {
            b.passLine = first;
            b.place4 = second;
            b.place10 = third;
        } else if (shape == 2) {
            b.dontPass = first;
            b.place4 = second;
            b.place10 = third;
        } else {
            b.place6 = first;
            b.hard8 = second;
            b.place8 = third;
        }
    }

    // --- isolation discipline -------------------------------------------------

    function _before() internal view returns (bool open, bool midDay, bytes32 h) {
        open = game.rngLocked();
        midDay = !open && _requestActive();
        if (open || midDay) h = _setHash();
    }

    function _after(bool open, bool midDay, bytes32 h0) internal {
        if (!open && !midDay) return;
        if (open) ghost_inWindowCrapsActions++;
        if (midDay) ghost_midDayInWindowCrapsActions++;
        if (_setHash() != h0) ghost_inWindowGameSetMutations++;
    }

    /// @dev One digest over BOTH enumerated sets (daily: day word, cursor, dailyIdx; mid-day: the
    ///      reserved leaf, LR_MID_DAY, ticketWriteSlot, vrfRequestId, rngRequestTime, rngLockedFlag)
    ///      plus the next leaf the craps table would bind.
    function _setHash() internal view returns (bytes32) {
        uint24 day = game.currentDayView();
        uint256 cursor = _cursor();
        uint256 reserved = _lootboxRngWord(uint48(cursor ^ 1));
        uint256 raw0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return keccak256(
            abi.encode(
                _rngWordByDay(day),
                cursor,
                reserved,
                _lootboxRngWord(uint48(cursor)),
                _lootboxRngWord(uint48(cursor ^ 1)),
                (raw0 >> (DAILY_IDX_BYTE_OFF * 8)) & 0xFFFFFF,
                (raw0 >> (RNG_REQUEST_TIME_BYTE_OFF * 8)) & RNG_REQUEST_TIME_MASK,
                (raw0 >> (RNG_LOCKED_FLAG_BYTE_OFF * 8)) & 0xFF,
                (raw0 >> (TICKET_WRITE_SLOT_BYTE_OFF * 8)) & 0xFF,
                uint256(vm.load(address(game), bytes32(VRF_REQUEST_ID_SLOT))),
                (uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK
            )
        );
    }

    // --- authoritative slot reads ----------------------------------------------

    function _rngWordByDay(uint24 day) internal view returns (uint256) {
        return RecyclingState.dailyWord(address(game), uint24(day));
    }

    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return uint256(bytes32(RecyclingState.word(address(game), uint48(index))));
    }

    function _cursor() internal view returns (uint256) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _finishHumanRead() internal {
        if (game.rngLocked() || _requestActive()) return;
        uint48 read = RecyclingState.readBuffer(address(game));
        if (RecyclingState.word(address(game), read) == 0) return;
        for (uint256 i; i < 100 && !game.boxIndexComplete(read); i++) {
            try game.openBoxes(512) {} catch { return; }
        }
    }

    function _requestActive() internal view returns (bool) {
        return uint256(vm.load(address(game), bytes32(0))) & (uint256(1) << 254) != 0;
    }

    function _rngRequestTime() internal view returns (uint256) {
        uint256 raw = uint256(vm.load(address(game), bytes32(uint256(0))));
        return (raw >> (RNG_REQUEST_TIME_BYTE_OFF * 8)) & RNG_REQUEST_TIME_MASK;
    }

    function _unfulfilledRequestId() internal view returns (uint256) {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return 0;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        return fulfilled ? 0 : reqId;
    }
}
