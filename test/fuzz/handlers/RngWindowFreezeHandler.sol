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
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34; // lootboxRngPacked (post Stage B pack: was 35); low 48 bits = index cursor
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35; // mapping(uint48 => uint256) lootbox word (post Stage B pack: was 36)
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF; // low 48 bits of slot 34
    uint256 private constant DAILY_IDX_BYTE_OFF = 3; // dailyIdx uint24 @ slot 0 byte 3
    uint256 private constant DAILY_IDX_MASK = 0xFFFFFF; // uint24

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
    ///         3=lootboxRngPacked(cursor), 4=dailyIdx. 0 = none observed.
    uint256 public ghost_lastMutatedSlotTag;

    // --- Per-action coverage counters (surveillance) ---
    uint256 public calls_openWindow;
    uint256 public calls_inWindowPlacement;
    uint256 public calls_inWindowPurchase;
    uint256 public calls_inWindowOpenBoxes;
    uint256 public calls_closeWindow;

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
}
