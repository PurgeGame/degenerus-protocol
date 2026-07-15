// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title RngWindowFreezeHandler — the FUZZ-02 RNG-FREEZE durable-invariant action handler.
///
/// @notice Promotes the scattered scenario freeze proofs (RngFreezeAndRemovalProofs placement/
///         resolve guards, V56FreezeSolvency stamped-day open, the RngIndexDrainOrdering ghost
///         binding) into ONE always-on fuzzed property: across any action sequence, no player-
///         controllable call taken WHILE THE VRF WINDOW IS OPEN mutates a storage slot the pending
///         consumption reads. Built on the v45 north-star — trace BACKWARD from the daily/lootbox
///         consumer, ENUMERATE every in-window SLOAD (not only the VRF-derived seeds; the non-VRF
///         cursors read alongside the word are a distinct bug class), and assert byte-equality
///         across an isolated in-window player action.
///
/// @dev THE FREEZE WINDOW. `advanceGame()` at the day boundary fires the daily VRF request and
///      latches `rngLockedFlag = true` / `rngRequestTime = block.timestamp` (AdvanceModule). From
///      that moment until `mockVRF.fulfillRandomWords` delivers the word (which clears the latch),
///      `rngLocked() == true` — that interval IS the open window. The daily consumption that runs
///      when the word lands reads the enumerated slot set below; a player must not be able to
///      steer any of them while the outcome is still unknown.
///
///      THE ENUMERATED IN-WINDOW SLOAD SET (the backward trace), with AUTHORITATIVE slots taken
///      from 380-01-LAYOUT-KEY (c4d48008; the v61 PACK shift is region-dependent — these are the
///      confirmed post-fold values, matching RngFreezeAndRemovalProofs 34/35 and V56FreezeSolvency
///      10/34/35; NOT the stale VRFPathHandler 37/38 literals):
///        (1) rngWordByDay[currentDay]         — slot 10  : the VRF-DERIVED day word the daily
///                                                          consumption resolves against.
///        (2) lootboxRngWordByIndex[index]     — slot 35  : the VRF-DERIVED lootbox word.
///        (3) lootboxRngPacked                 — slot 34  : the packed lootbox cursor — its low 48
///                                                          bits (lootboxRngIndex) are the NON-VRF
///                                                          index the consumption reads ALONGSIDE
///                                                          the word ([[feedback_rng_window_storage_read_freshness]]).
///        (4) dailyIdx                         — slot 0, byte 3 (uint24) : the NON-VRF day cursor
///                                                          the consumption keys against. Included
///                                                          precisely because it is NOT a seed —
///                                                          a non-VRF in-window read is its own
///                                                          bug class.
///
///      ISOLATING THE EXEMPT MUTATOR. advanceGame is the heartbeat that LEGITIMATELY progresses the
///      window (it is the v45-exempt mutator). To attribute a change to a PLAYER action rather than
///      the heartbeat, every in-window player action snapshots the enumerated set immediately
///      BEFORE the call and immediately AFTER the call alone (no advance in between) — a frozen
///      slot must be byte-equal across the player action in isolation. ghost_frozenSlotMutations
///      counts only player-attributable changes; advanceGame's own progression is never measured.
///
///      NON-VACUITY. ghost_windowsOpened / ghost_inWindowActions must both be > 0 after a run, else
///      the freeze assertion is vacuous (the window never opened or no in-window action fired). The
///      invariant test gates acceptance on both being positive.
///
///      Test-only: NO contracts/*.sol is mutated. The only vm.store is the standard slot-34
///      lootbox-index seed (mirroring RngFreezeAndRemovalProofs.setUp) so an active lootbox index
///      exists to snapshot. Slot reads are vm.load against the authoritative layout.
contract RngWindowFreezeHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // -------------------------------------------------------------------------
    // Authoritative c4d48008 storage layout (380-01-LAYOUT-KEY; confirmed against
    // RngFreezeAndRemovalProofs + V56FreezeSolvency — NOT the stale VRFPath literals).
    // -------------------------------------------------------------------------
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint24 => uint256) day word
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // lootboxRngPacked (post Stage B pack: was 35); low 48 bits = index cursor
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34; // mapping(uint48 => uint256) lootbox word (post Stage B pack: was 36)
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF; // low 48 bits of slot 34
    uint256 private constant DAILY_IDX_BYTE_OFF = 3; // dailyIdx uint24 @ slot 0 byte 3
    uint256 private constant DAILY_IDX_MASK = 0xFFFFFF; // uint24

    // Mid-day lootbox window fields (same 388-01-LAYOUT-KEY layout; slot-0 roots are the
    // StorageFoundation-canaried offsets).
    uint256 private constant VRF_REQUEST_ID_SLOT = 4; // uint256 vrfRequestId
    uint256 private constant RNG_REQUEST_TIME_BYTE_OFF = 6; // rngRequestTime uint48 @ slot 0 bytes 6-11
    uint256 private constant RNG_REQUEST_TIME_MASK = 0xFFFFFFFFFFFF; // uint48
    uint256 private constant RNG_LOCKED_FLAG_BYTE_OFF = 19; // bool rngLockedFlag @ slot 0 byte 19
    uint256 private constant TICKET_WRITE_SLOT_BYTE_OFF = 26; // bool ticketWriteSlot @ slot 0 byte 26
    uint256 private constant LR_MID_DAY_SHIFT = 224; // LR_MID_DAY flag bits of slot 34
    uint256 private constant LR_MID_DAY_MASK = 0xFF;
    uint256 private constant LR_THRESHOLD_SHIFT = 112; // lootboxRngThreshold (milli-ETH) bits of slot 34
    uint256 private constant LR_THRESHOLD_MASK = 0xFFFFFFFFFFFFFFFF;
    uint256 private constant LR_ETH_SCALE = 1e15; // milli-ETH packing scale

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — degenerette first-spin salt

    // -------------------------------------------------------------------------
    // Ghost surface (the invariant reads these)
    // -------------------------------------------------------------------------

    /// @notice Count of distinct VRF windows the handler drove open (rngLocked()==true observed).
    ///         Must be > 0 for the freeze property to be non-vacuous.
    uint256 public ghost_windowsOpened;

    /// @notice Count of player-controllable actions ATTEMPTED while the window was open. Must be
    ///         > 0 for the freeze property to be non-vacuous (an attempt is counted whether the
    ///         contract's freeze guard reverts it or it runs — both are valid freeze outcomes).
    uint256 public ghost_inWindowActions;

    /// @notice THE PROPERTY. Count of in-window player actions that, in ISOLATION (no advance in
    ///         between), mutated an enumerated consumed slot. MUST stay 0 — any increment is a
    ///         freeze violation (a player steered an as-yet-unknown random outcome).
    uint256 public ghost_frozenSlotMutations;

    /// @notice Which enumerated slot last flipped (diagnostic): 1=rngWordByDay, 2=lootboxWord,
    ///         3=lootboxRngPacked(cursor), 4=dailyIdx; mid-day set: 5=lootbox index cursor,
    ///         6=reserved lootbox leaf, 7=LR_MID_DAY flag, 8=ticketWriteSlot, 9=vrfRequestId,
    ///         10=rngRequestTime, 11=rngLockedFlag. 0 = none observed.
    uint256 public ghost_lastMutatedSlotTag;

    /// @notice Count of distinct MID-DAY lootbox VRF windows the handler drove open
    ///         (rngRequestTime != 0 with rngLocked() == false observed). Must be > 0 for the
    ///         mid-day freeze property to be non-vacuous.
    uint256 public ghost_midDayWindowsOpened;

    /// @notice Count of player-controllable actions ATTEMPTED while a MID-DAY window was open.
    ///         Must be > 0 for the mid-day freeze property to be non-vacuous.
    uint256 public ghost_midDayInWindowActions;

    // --- Per-action coverage counters (surveillance) ---
    uint256 public calls_openWindow;
    uint256 public calls_inWindowPlacement;
    uint256 public calls_inWindowPurchase;
    uint256 public calls_inWindowOpenBoxes;
    uint256 public calls_closeWindow;
    uint256 public calls_openMidDayWindow;
    uint256 public calls_midDayPlacement;
    uint256 public calls_midDayPurchase;
    uint256 public calls_midDayOpenBoxes;
    uint256 public calls_closeMidDayWindow;

    // -------------------------------------------------------------------------
    // Actors — disjoint base 0x60000 (unoccupied by every existing handler)
    // -------------------------------------------------------------------------
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0x60000 + i));
            actors.push(actor);
            vm.deal(actor, 1_000 ether);
            // The resolve/open sub-calls run with msg.sender == game (the documented crank
            // relaxation), so each actor approves the game as operator — lets an in-window
            // placement/resolve reach the contract's freeze guard rather than an approval revert.
            vm.prank(actor);
            game.setOperatorApproval(address(game), true);
        }

        // Seed lootboxRngIndex = 1 (word stays 0) so an ACTIVE lootbox index exists to snapshot
        // and so placeDegeneretteBet's index!=0 / word==0 placement precondition can hold. This is
        // the identical slot-34 index seed RngFreezeAndRemovalProofs.setUp uses — a field-isolated
        // cursor write, NOT a balance or word write.
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT)));
        lrPacked = (lrPacked & ~LR_INDEX_MASK) | uint256(1);
        vm.store(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT), bytes32(lrPacked));
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =========================================================================
    // Action: openWindow — drive the daily VRF request so rngLocked() latches true
    // =========================================================================

    /// @notice Satisfy the daily purchase gate with a small actor buy, then advanceGame() to fire
    ///         the daily VRF request — which latches rngLockedFlag = true (the window opens). Does
    ///         NOT fulfill the request (that is closeWindow's job), so the window stays open for the
    ///         in-window action handlers. Idempotent: if the window is already open it just records.
    function openWindow(uint256 actorSeed) external useActor(actorSeed) {
        calls_openWindow++;
        _driveWindowOpen(actorSeed);
    }

    /// @dev Drive the daily VRF window OPEN with the current actor and return whether rngLocked() latched.
    ///      Factored out so the in-window actions can SELF-PRIME the window (guaranteeing they execute
    ///      inside an open window regardless of fuzzer call ordering — the freeze property is otherwise
    ///      vacuously green if an in-window action never coincides with an open window). On a successful
    ///      latch it records ghost_windowsOpened and snapshots the enumerated consumed set at request time.
    function _driveWindowOpen(uint256 actorSeed) internal returns (bool open) {
        if (game.gameOver()) return false;

        // If a window is already open, nothing to drive — record (re-counts an already-open observation)
        // and reuse the existing request-time snapshot.
        if (game.rngLocked()) {
            ghost_windowsOpened++;
            return true;
        }

        // Small daily-gate buy so advanceGame has a reason to request the daily word.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 oneTicket = priceWei; // 400 entries == 1 price (project_ticket_entry_price_units)
        if (oneTicket != 0 && oneTicket <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: oneTicket}(currentActor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }

        // Advance until a daily request is in flight (rngLocked latches). The daily request only fires at a
        // NEW day boundary; after a prior window closed, the game sits on the current day until time passes.
        // Each iteration warps a full day forward (crossing the JACKPOT_RESET_TIME boundary) so a fresh
        // daily request becomes due, then advances. Capped; intermediate non-daily (lootbox) requests are
        // fulfilled to keep progressing (they are NOT the window we measure — windowsOpened is recorded only
        // when rngLocked() is observed true after the advance). Time passing between days is the heartbeat's
        // natural rhythm (the v45-exempt progression), not a player-attributable mutation.
        for (uint256 i; i < 8 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(currentActor);
            try game.advanceGame() {} catch {}
            if (game.rngLocked()) break;
            // Not yet latched — clear any non-daily in-flight request to keep progressing.
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("openw", actorSeed, i))) | 1) {} catch {}
                }
            }
        }

        open = game.rngLocked();
        if (open) {
            ghost_windowsOpened++;
            _snapshotEnumeratedSet();
        }
    }

    // =========================================================================
    // In-window action: degenerette placement (the SAFE-04 placement-guard surface)
    // =========================================================================

    /// @notice Attempt a degenerette placement WHILE the window is open. The contract's freeze
    ///         guard (RngNotReady once an index has a word, DegeneretteModule) may revert it — that
    ///         is a valid freeze outcome. Either way the action was attempted; the isolation check
    ///         asserts it did not move any enumerated consumed slot in isolation.
    function tryInWindowPlacement(uint256 actorSeed, uint128 amtSeed, uint32 ticketSeed) external useActor(actorSeed) {
        calls_inWindowPlacement++;
        // Self-prime: open the window if the fuzzer did not just open one, so this action always runs
        // INSIDE an open window (else the freeze property would be vacuous). _driveWindowOpen snapshots
        // the enumerated set at request time on a fresh latch.
        if (!_driveWindowOpen(actorSeed)) return; // could not open (gameOver) — nothing to exercise
        ghost_inWindowActions++;

        _snapshotEnumeratedSet();
        uint128 amt = uint128(bound(uint256(amtSeed), 0.001 ether, 0.05 ether));
        if (amt > currentActor.balance) {
            _checkFrozenAfterIsolatedAction();
            return;
        }
        vm.prank(currentActor);
        try game.placeDegeneretteBet{value: amt}(address(0), 0, amt, 1, ticketSeed, 0) {} catch {}
        _checkFrozenAfterIsolatedAction();
    }

    // =========================================================================
    // In-window action: a ticket / lootbox purchase
    // =========================================================================

    /// @notice Attempt a purchase WHILE the window is open. advanceGame is the only exempt mutator;
    ///         a plain purchase must not touch the frozen word/cursor set. Isolation-checked.
    function tryInWindowPurchase(uint256 actorSeed, uint256 qtySeed, uint256 boxSeed) external useActor(actorSeed) {
        calls_inWindowPurchase++;
        if (game.gameOver()) return;
        // Self-prime the window so the purchase always runs inside an open window (non-vacuity).
        if (!_driveWindowOpen(actorSeed)) return;
        ghost_inWindowActions++;

        _snapshotEnumeratedSet();
        uint256 qty = bound(qtySeed, 400, 2000); // whole-ticket multiples
        uint256 boxAmt = bound(boxSeed, 0, 1 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * qty) / 400 + boxAmt + 0.01 ether;
        if (cost > currentActor.balance) {
            _checkFrozenAfterIsolatedAction();
            return;
        }
        vm.prank(currentActor);
        try game.purchase{value: cost}(currentActor, qty, boxAmt, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        _checkFrozenAfterIsolatedAction();
    }

    // =========================================================================
    // In-window action: openBoxes (the lootbox-resolve freeze surface)
    // =========================================================================

    /// @notice Attempt openBoxes WHILE the window is open. Pre-word the autoOpen cursor orphan gate
    ///         + the openLootBox RngNotReady guard skip the open (SAFE-04). The isolation check
    ///         asserts the call did not move the frozen word/cursor set.
    function tryInWindowOpenBoxes(uint256 actorSeed, uint256 maxSeed) external useActor(actorSeed) {
        calls_inWindowOpenBoxes++;
        // Self-prime the window so openBoxes always runs inside an open window (non-vacuity).
        if (!_driveWindowOpen(actorSeed)) return;
        ghost_inWindowActions++;

        _snapshotEnumeratedSet();
        uint256 maxCount = bound(maxSeed, 1, 200);
        vm.prank(currentActor);
        try game.openBoxes(maxCount) {} catch {}
        _checkFrozenAfterIsolatedAction();
    }

    // =========================================================================
    // Action: closeWindow — fulfill the pending VRF (the exempt heartbeat completion)
    // =========================================================================

    /// @notice Close the window: fulfill the in-flight daily VRF request (which STORES rngWordCurrent but
    ///         leaves rngLockedFlag set — AdvanceModule.rawFulfillRandomWords only buffers the word for the
    ///         daily branch), THEN advanceGame to drive the day processing that calls _unlockRng (clearing
    ///         rngLockedFlag). This is the EXEMPT heartbeat completing — it is NOT measured against the
    ///         freeze property; it simply re-opens the fuzzer to drive a fresh window next round. The
    ///         player-attributable freeze check already ran in isolation at each in-window action above.
    function closeWindow(uint256 wordSeed) external {
        calls_closeWindow++;
        _closeDailyWindow(wordSeed);
    }

    /// @dev Internal body of closeWindow, factored out so the mid-day driver can clear a daily
    ///      window that stands in the way of opening a mid-day one (requestLootboxRng reverts
    ///      RngLocked while the daily window is open).
    function _closeDailyWindow(uint256 wordSeed) internal {
        if (!game.rngLocked()) return;
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (!fulfilled) {
            // Non-zero word (the contract treats word==0 as not-yet-landed).
            try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("closew", wordSeed))) | 1) {} catch {}
        }
        // Fulfillment only buffers the daily word; the lock clears when a subsequent advanceGame processes
        // the day (the EXEMPT heartbeat). Drive it until rngLocked() falls (capped).
        for (uint256 i; i < 8 && game.rngLocked(); i++) {
            try game.advanceGame() {} catch {}
        }
    }

    // =========================================================================
    // MID-DAY LOOTBOX WINDOW — the second freeze window shape.
    //
    // requestLootboxRng (AdvanceModule) opens a lootbox-only VRF window that sets NEITHER
    // rngLockedFlag NOR prizePoolFrozen: the in-flight marker is rngRequestTime != 0 with
    // rngLocked() == false. The pending consumption is the mid-day rawFulfillRandomWords branch —
    // it reads the LR_INDEX cursor (landing index = LR_INDEX - 1), writes the reserved
    // lootboxRngWordByIndex leaf, and the NEXT advance processes the ticket batch frozen (buffer
    // swap + LR_MID_DAY=1) at request time. The backward trace of that consumption gives the
    // enumerated mid-day SLOAD set:
    //   (5)  LR_INDEX cursor            — slot 34 low 48 : where the pending word will land (-1).
    //   (6)  lootboxRngWordByIndex[N-1] — slot 35 leaf   : the reserved landing leaf (0 until the
    //                                                      exempt fulfillment writes it).
    //   (7)  LR_MID_DAY flag            — slot 34 bits 224.. : routes the frozen ticket batch.
    //   (8)  ticketWriteSlot            — slot 0 byte 26 : the read/write buffer selector frozen
    //                                                      by the request-time swap.
    //   (9)  vrfRequestId               — slot 4         : the fulfillment's request-match gate.
    //   (10) rngRequestTime             — slot 0 bytes 6-11 : the in-flight marker (a player
    //                                                      clear would permit an entropy reroll).
    //   (11) rngLockedFlag              — slot 0 byte 19 : the fulfillment branch selector (flip
    //                                                      would reroute the word to the daily buffer).
    // Same isolation discipline as the daily set: snapshot immediately before the player action,
    // re-read immediately after it alone; advanceGame / requestLootboxRng / the VRF callback are
    // the exempt machinery and are never measured.
    // =========================================================================

    /// @dev The mid-day window predicate: a VRF request is in flight (rngRequestTime stamped) but
    ///      the daily lock is NOT held — exactly the requestLootboxRng in-flight state.
    function _midDayWindowOpen() internal view returns (bool) {
        return _rngRequestTime() != 0 && !game.rngLocked();
    }

    /// @notice Drive a mid-day lootbox VRF window open so the fuzzer can act inside it.
    function openMidDayWindow(uint256 actorSeed) external useActor(actorSeed) {
        calls_openMidDayWindow++;
        _driveMidDayOpen(actorSeed);
    }

    /// @dev Drive the MID-DAY window open with the current actor; returns whether it latched.
    ///      Preconditions of requestLootboxRng, satisfied in order: no daily lock (close it),
    ///      today's daily word recorded (drive a full daily cycle), pending lootbox ETH above the
    ///      packed threshold (a box purchase), then the request itself. Capped ladder — every
    ///      sub-step is the exempt machinery, never measured against the property.
    function _driveMidDayOpen(uint256 actorSeed) internal returns (bool open) {
        for (uint256 i; i < 3; i++) {
            if (game.gameOver()) return false;

            if (_midDayWindowOpen()) {
                ghost_midDayWindowsOpened++;
                _snapshotMidDaySet();
                return true;
            }

            // A daily window blocks requestLootboxRng (RngLocked) — complete it first.
            if (game.rngLocked()) {
                _closeDailyWindow(actorSeed + i);
                if (game.rngLocked()) return false; // could not complete the heartbeat
            }

            // requestLootboxRng needs TODAY's daily word consumed and recorded.
            if (_rngWordByDay(game.currentDayView()) == 0) {
                if (!_driveWindowOpen(actorSeed + i)) return false;
                _closeDailyWindow(actorSeed + i);
                if (game.rngLocked() || game.gameOver()) return false;
            }

            // Pending lootbox ETH must clear the packed milli-ETH threshold (default 1 ether).
            uint256 thresholdWei =
                ((uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) >> LR_THRESHOLD_SHIFT) &
                    LR_THRESHOLD_MASK) * LR_ETH_SCALE;
            uint256 boxAmt = thresholdWei + 0.1 ether;
            (, , , , uint256 priceWei) = game.purchaseInfo();
            uint256 cost = priceWei + boxAmt; // 1 whole ticket (400 entries) + the box leg
            if (cost > currentActor.balance) return false;
            vm.prank(currentActor);
            try game.purchase{value: cost}(currentActor, 400, boxAmt, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}

            vm.prank(currentActor);
            try game.requestLootboxRng() {} catch {}

            if (_midDayWindowOpen()) {
                ghost_midDayWindowsOpened++;
                _snapshotMidDaySet();
                return true;
            }
        }
        return false;
    }

    /// @notice Attempt a degenerette placement WHILE the mid-day window is open. Isolation-checked
    ///         against the enumerated mid-day set.
    function tryMidDayPlacement(uint256 actorSeed, uint128 amtSeed, uint32 ticketSeed) external useActor(actorSeed) {
        calls_midDayPlacement++;
        if (!_driveMidDayOpen(actorSeed)) return;
        ghost_midDayInWindowActions++;

        _snapshotMidDaySet();
        uint128 amt = uint128(bound(uint256(amtSeed), 0.001 ether, 0.05 ether));
        if (amt > currentActor.balance) {
            _checkMidDayFrozenAfterIsolatedAction();
            return;
        }
        vm.prank(currentActor);
        try game.placeDegeneretteBet{value: amt}(address(0), 0, amt, 1, ticketSeed, 0) {} catch {}
        _checkMidDayFrozenAfterIsolatedAction();
    }

    /// @notice Attempt a ticket/lootbox purchase WHILE the mid-day window is open. New purchases
    ///         must accrue to the NEXT lootbox index / the WRITE ticket buffer — never move the
    ///         reserved leaf, the landing cursor, or the frozen buffer selector. Isolation-checked.
    function tryMidDayPurchase(uint256 actorSeed, uint256 qtySeed, uint256 boxSeed) external useActor(actorSeed) {
        calls_midDayPurchase++;
        if (!_driveMidDayOpen(actorSeed)) return;
        ghost_midDayInWindowActions++;

        _snapshotMidDaySet();
        uint256 qty = bound(qtySeed, 400, 2000); // whole-ticket multiples
        uint256 boxAmt = bound(boxSeed, 0, 1 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * qty) / 400 + boxAmt + 0.01 ether;
        if (cost > currentActor.balance) {
            _checkMidDayFrozenAfterIsolatedAction();
            return;
        }
        vm.prank(currentActor);
        try game.purchase{value: cost}(currentActor, qty, boxAmt, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        _checkMidDayFrozenAfterIsolatedAction();
    }

    /// @notice Attempt openBoxes WHILE the mid-day window is open. Boxes at the reserved (word-less)
    ///         index are skipped by the contract's RngNotReady guard; either way the call must not
    ///         move the enumerated mid-day set. Isolation-checked.
    function tryMidDayOpenBoxes(uint256 actorSeed, uint256 maxSeed) external useActor(actorSeed) {
        calls_midDayOpenBoxes++;
        if (!_driveMidDayOpen(actorSeed)) return;
        ghost_midDayInWindowActions++;

        _snapshotMidDaySet();
        uint256 maxCount = bound(maxSeed, 1, 200);
        vm.prank(currentActor);
        try game.openBoxes(maxCount) {} catch {}
        _checkMidDayFrozenAfterIsolatedAction();
    }

    /// @notice Close the mid-day window: fulfill the in-flight lootbox request. The mid-day
    ///         rawFulfillRandomWords branch finalizes directly — lands the word at LR_INDEX - 1 and
    ///         clears vrfRequestId / rngRequestTime (no advanceGame needed). Exempt machinery.
    function closeMidDayWindow(uint256 wordSeed) external {
        calls_closeMidDayWindow++;
        if (!_midDayWindowOpen()) return;
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (!fulfilled) {
            try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("closemid", wordSeed))) | 1) {} catch {}
        }
    }

    // =========================================================================
    // The enumerated-slot snapshot + isolation freeze check
    // =========================================================================

    // Snapshot storage of the enumerated consumed set, captured at request time / before each
    // isolated in-window action.
    uint256 private _snapDayWord; // rngWordByDay[currentDay]
    uint256 private _snapLootboxWord; // lootboxRngWordByIndex[activeIndex]
    uint256 private _snapLootboxCursor; // lootboxRngPacked low 48 bits (the index cursor)
    uint256 private _snapDailyIdx; // dailyIdx (the non-VRF day cursor)
    uint24 private _snapDay; // the day key the word snapshot was taken at
    uint48 private _snapIndex; // the lootbox index the word snapshot was taken at

    /// @dev Snapshot every enumerated in-window SLOAD. Keyed at the CURRENT day / active index so
    ///      the post-action re-read compares the SAME mapping leaf (a fresh leaf would be a false
    ///      positive — the consumption reads the leaf live at request time).
    function _snapshotEnumeratedSet() internal {
        _snapDay = game.currentDayView();
        _snapIndex = _activeLootboxIndex();
        _snapDayWord = _rngWordByDay(_snapDay);
        _snapLootboxWord = _lootboxRngWord(_snapIndex);
        _snapLootboxCursor = _lootboxRngIndexCursor();
        _snapDailyIdx = _dailyIdx();
    }

    /// @dev Re-read the enumerated set after an ISOLATED in-window player action (no advance ran in
    ///      between) and flag any change. Because advanceGame — the only legitimate mutator of this
    ///      set — was NOT called between the snapshot and here, any delta is attributable to the
    ///      player action alone. Compares the SAME day/index leaf the snapshot used.
    function _checkFrozenAfterIsolatedAction() internal {
        if (_rngWordByDay(_snapDay) != _snapDayWord) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 1;
        }
        if (_lootboxRngWord(_snapIndex) != _snapLootboxWord) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 2;
        }
        if (_lootboxRngIndexCursor() != _snapLootboxCursor) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 3;
        }
        if (_dailyIdx() != _snapDailyIdx) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 4;
        }
    }

    // =========================================================================
    // The enumerated MID-DAY snapshot + isolation freeze check
    // =========================================================================

    uint256 private _snapMidCursor; // LR_INDEX (slot 34 low 48)
    uint256 private _snapMidLeafWord; // lootboxRngWordByIndex[LR_INDEX - 1]
    uint256 private _snapMidMidDayFlag; // LR_MID_DAY bits
    uint256 private _snapMidTicketWriteSlot; // ticketWriteSlot byte
    uint256 private _snapMidVrfRequestId; // vrfRequestId
    uint256 private _snapMidRngRequestTime; // rngRequestTime (uint48)
    uint256 private _snapMidRngLockedFlag; // rngLockedFlag byte
    uint48 private _snapMidLeafIndex; // the reserved landing index the leaf snapshot keyed

    /// @dev Snapshot every enumerated mid-day SLOAD. The leaf is keyed at the CURRENT reserved
    ///      landing index (LR_INDEX - 1) so the post-action re-read compares the SAME mapping leaf
    ///      the pending fulfillment will write.
    function _snapshotMidDaySet() internal {
        _snapMidCursor = _lootboxRngIndexCursor();
        _snapMidLeafIndex = _snapMidCursor == 0 ? 0 : uint48(_snapMidCursor - 1);
        _snapMidLeafWord = _lootboxRngWord(_snapMidLeafIndex);
        _snapMidMidDayFlag = _lrMidDayFlag();
        _snapMidTicketWriteSlot = _ticketWriteSlotRaw();
        _snapMidVrfRequestId = _vrfRequestId();
        _snapMidRngRequestTime = _rngRequestTime();
        _snapMidRngLockedFlag = _rngLockedFlagRaw();
    }

    /// @dev Re-read the enumerated mid-day set after an ISOLATED in-window player action (no
    ///      advance / request / fulfillment ran in between) and flag any change — identical
    ///      discipline to _checkFrozenAfterIsolatedAction, over the mid-day consumption's set.
    function _checkMidDayFrozenAfterIsolatedAction() internal {
        if (_lootboxRngIndexCursor() != _snapMidCursor) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 5;
        }
        if (_lootboxRngWord(_snapMidLeafIndex) != _snapMidLeafWord) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 6;
        }
        if (_lrMidDayFlag() != _snapMidMidDayFlag) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 7;
        }
        if (_ticketWriteSlotRaw() != _snapMidTicketWriteSlot) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 8;
        }
        if (_vrfRequestId() != _snapMidVrfRequestId) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 9;
        }
        if (_rngRequestTime() != _snapMidRngRequestTime) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 10;
        }
        if (_rngLockedFlagRaw() != _snapMidRngLockedFlag) {
            ghost_frozenSlotMutations++;
            ghost_lastMutatedSlotTag = 11;
        }
    }

    // =========================================================================
    // Authoritative slot reads (vm.load against the 380-01-LAYOUT-KEY layout)
    // =========================================================================

    function _rngWordByDay(uint24 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT))));
    }

    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(index), LOOTBOX_RNG_WORD_SLOT))));
    }

    function _lootboxRngIndexCursor() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) & LR_INDEX_MASK;
    }

    function _activeLootboxIndex() internal view returns (uint48) {
        return uint48(_lootboxRngIndexCursor());
    }

    function _dailyIdx() internal view returns (uint256) {
        uint256 raw = uint256(vm.load(address(game), bytes32(uint256(0))));
        return (raw >> (DAILY_IDX_BYTE_OFF * 8)) & DAILY_IDX_MASK;
    }

    function _rngRequestTime() internal view returns (uint256) {
        uint256 raw = uint256(vm.load(address(game), bytes32(uint256(0))));
        return (raw >> (RNG_REQUEST_TIME_BYTE_OFF * 8)) & RNG_REQUEST_TIME_MASK;
    }

    function _rngLockedFlagRaw() internal view returns (uint256) {
        uint256 raw = uint256(vm.load(address(game), bytes32(uint256(0))));
        return (raw >> (RNG_LOCKED_FLAG_BYTE_OFF * 8)) & 0xFF;
    }

    function _ticketWriteSlotRaw() internal view returns (uint256) {
        uint256 raw = uint256(vm.load(address(game), bytes32(uint256(0))));
        return (raw >> (TICKET_WRITE_SLOT_BYTE_OFF * 8)) & 0xFF;
    }

    function _vrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(VRF_REQUEST_ID_SLOT)));
    }

    function _lrMidDayFlag() internal view returns (uint256) {
        return
            (uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK;
    }

    // =========================================================================
    // Falsifiability seam (test-only) — proves the freeze detector is not vacuous
    // =========================================================================

    /// @notice FALSIFIABILITY HOOK. Seeds an in-window mutation of an enumerated consumed slot against the
    ///         LAST snapshot (taken at openWindow), runs the isolation freeze-check, then RESTORES the slot
    ///         so the seeded break never leaks into the campaign's real invariant. Used only by
    ///         RngWindowFreeze.inv.t.sol::test_invariantCatchesSeededInWindowMutation to prove
    ///         _checkFrozenAfterIsolatedAction actually registers a delta on a snapshotted slot — i.e. the
    ///         freeze invariant genuinely catches a violation rather than being unfalsifiably green.
    /// @dev Mutates rngWordByDay[_snapDay] (the VRF-derived day word the snapshot keyed at request time) by
    ///      a non-zero delta — exactly the in-window seed-steering the freeze property forbids — then runs
    ///      the SAME isolation comparison the real in-window actions use, RETURNING whether a delta was
    ///      observed. It deliberately does NOT touch the campaign's ghost_frozenSlotMutations (that counter
    ///      is the live property; a seeded falsification must never pollute it — the fuzzer can also call
    ///      this selector, so it is excluded from the campaign in the invariant setUp AND made
    ///      counter-neutral here as defence-in-depth). The contract slot is restored immediately. A `true`
    ///      return proves the detector registers a known in-window violation — the falsifiability guarantee.
    function debugSeedInWindowMutationAndCheck() external returns (bool detected) {
        bytes32 dayWordSlot = keccak256(abi.encode(uint256(_snapDay), RNG_WORD_BY_DAY_SLOT));
        uint256 original = uint256(vm.load(address(game), dayWordSlot));

        // Seed the in-window mutation: flip the snapshotted day word to a different value.
        vm.store(address(game), dayWordSlot, bytes32(original ^ uint256(keccak256("rngfreeze_falsify"))));

        // Run the identical isolation comparison the live in-window actions use, but score it locally so the
        // campaign's property counter is never moved by a deliberately-seeded break.
        detected = (_rngWordByDay(_snapDay) != _snapDayWord);

        // Restore — the seeded break exists only for the duration of the detection.
        vm.store(address(game), dayWordSlot, bytes32(original));
    }

    /// @notice FALSIFIABILITY HOOK (mid-day counterpart of debugSeedInWindowMutationAndCheck).
    ///         Seeds a mutation of the RESERVED lootbox landing leaf against the last mid-day
    ///         snapshot — exactly the pre-fulfillment word-steering the mid-day freeze property
    ///         forbids — runs the same isolation comparison the live tryMidDay* actions use, then
    ///         RESTORES the slot. Counter-neutral for the same defence-in-depth reason: the
    ///         campaign's live property counter is never moved by a deliberately-seeded break, and
    ///         the selector is excluded from the fuzz campaign in the invariant setUp.
    function debugSeedMidDayMutationAndCheck() external returns (bool detected) {
        bytes32 leafSlot = keccak256(abi.encode(uint256(_snapMidLeafIndex), LOOTBOX_RNG_WORD_SLOT));
        uint256 original = uint256(vm.load(address(game), leafSlot));

        vm.store(address(game), leafSlot, bytes32(original ^ uint256(keccak256("midday_falsify"))));

        detected = (_lootboxRngWord(_snapMidLeafIndex) != _snapMidLeafWord);

        vm.store(address(game), leafSlot, bytes32(original));
    }
}
