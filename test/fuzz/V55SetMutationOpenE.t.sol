// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title V55SetMutationOpenE -- The dedicated TST-04 proof: the v55.0 two-path open coexistence
///        (BOX-05, no shared mutable-state hazard), the NO-ORPHAN guard (a sub removed between stamp and
///        open gets NO free box, GameAfkingModule.sol:554-576), the streak-preserved swap-pop
///        (scorePlus1 survives the tombstone-reclaim), and the OPEN-E 4-protection regression
///        ([[open-e-operator-approval-trust-boundary]]).
///
/// @notice The two open routes are GENUINELY SEPARATE (no selector / queue overlap):
///   - HUMAN box open: `game.openBoxes(maxCount)` (DegenerusGame.sol:1787) walks `boxPlayers[index]`.
///   - AFKING box open: `game.mintFlip()`'s open leg (GameAfkingModule.sol:1000-1009, only when
///     !advanceDue) walks `_subscribers` via `_autoOpen`. The afking module's own `autoOpen` selector
///     COLLIDES with the human `autoOpen(uint256)` so it is NOT re-exposed on the Game (DegenerusGame.sol
///     :352-353) — the afking open is reached ONLY through `mintFlip`. The two paths share no mutable
///     state: distinct queues (`boxPlayers` vs `_subscribers`), distinct cursors (`boxCursor` vs
///     `_subOpenCursor`), distinct per-box records (`lootboxEth[index][player]` vs the warm Sub stamp).
///
/// @notice NO-ORPHAN (the load-bearing §3 guard): a box is STAMPED at the process STAGE (day D) but
///         OPENED later; it exists ONLY as (Sub stamp + lastAutoBoughtDay) with no cold ledger. The open
///         leg walks `_subscribers`, so ANY removal of the sub from `_subscribers` between stamp and open
///         ORPHANS the paid-for box (the player was debited at stamp, gets nothing) — and the process
///         STAGE's NO-ORPHAN guard (GameAfkingModule.sol:570) DOMINATES all four mutation paths
///         (re-stamp / cancel-reclaim / pass-evict / funding-kill) by leaving a pending-box sub ENTIRELY
///         untouched, so the contract itself never orphans. This proof asserts both: (a) the contract
///         never orphans a pending-box sub via the STAGE, and (b) IF the sub is removed from the set
///         (the orphan condition) the open leg materializes NO box for it.
///
/// @notice OPEN-E 4-protection (TST-04): consent-gate-at-subscribe (unapproved operator REVERTS) /
///         default-self (src=address(0) -> funder == self, byte-identical) / no-escalation (an operator
///         cannot widen the grant per-draw) / trust-the-sub temporal bound (a later revoke does not stop
///         an active sub).
///
/// @dev Builds on the 351-01-repaired DeployProtocol fixture (GameAfkingModule live). RE-DERIVED every
///      pinned slot via `forge inspect storage DegenerusGame` (the AfKing-standalone-layout constants are
///      WRONG). Test-only: no contracts/*.sol mutated.
contract V55SetMutationOpenE is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect DegenerusGame storageLayout`, post
    // Stage B Game-storage packing — corrected to authoritative values).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 53; // _subOf mapping root
    uint256 private constant SUBSCRIBERS_SLOT = 55; // _subscribers address[] (length here; data at keccak(56))
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 56; // _subscriberIndex mapping root (1-indexed)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit)

    // Sub packed-field byte offsets — the v56 compute-on-read re-pack (single 256-bit slot).
    // OFF_DAILY/OFF_VALIDTHROUGH did not move; scorePlus1/amount/day-markers shifted down.
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity     (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel (bytes 1..3)
    uint256 private constant OFF_SCOREPLUS1 = 5; // uint16 scorePlus1        (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 7; // uint24 amount            (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13; // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184;

    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // (a) Two-path coexistence (BOX-05 — no shared mutable-state hazard)
    // =========================================================================

    /// @notice An afking-stamp open and a HUMAN box open in the same fixture state do not corrupt each
    ///         other: opening the human box leaves the afking sub's pending-box stamp untouched, and
    ///         opening the afking box leaves the human box queue untouched. The two routes share no
    ///         mutable state (distinct queues / cursors / records).
    function testTwoPathOpenCoexistenceNoCrossCorruption() public {
        // v56 DROP (356-07, removed/adapted surface): the v55 two-path-SEPARATION assertion (a human
        // openBoxes leaves the afking stamp untouched) is superseded by the v56 LIVE-01 UNIFIED openBoxes
        // valve (commit 86a2d6c8), which calls drainAfkingBoxes FIRST then the human leg — so openBoxes(50)
        // now legitimately opens the afking box too (lastOpenedDay advances). The v56 two-path coexistence
        // (afking-first ordering, both cursors drain, lastOpenedDay monotone no-double-open, selector
        // isolation) is proven against the v56 valve by V56AfkingGasMarginal's LIVE-01 cases.
        vm.skip(true, "v56: unified openBoxes valve opens afking-first; coexistence re-proven in V56AfkingGasMarginal LIVE-01");
        // AFKING arm: a funded lootbox sub gets a stamped box via the STAGE.
        address afk = makeAddr("afk_player");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        _runStageNewDay(0xC0A1); // stamp the afking box (lastAutoBoughtDay set, lastOpenedDay < it)

        // HUMAN arm: a real lootbox buyer queues a box on the human path (boxPlayers).
        address human = makeAddr("human_player");
        vm.deal(human, 5 ether);
        vm.prank(human);
        game.purchase{value: 1.01 ether}(human, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth, false);

        // Settle so the afking open leg (mintFlip, !advanceDue) and the human autoOpen can run.
        _settleGame(0xC0A2);

        // Snapshot the afking sub's pending-box stamp BEFORE the human open.
        uint32 afkBoughtBefore = _lastBoughtDayOf(afk);
        uint32 afkOpenedBefore = _lastOpenedDayOf(afk);
        assertGt(afkBoughtBefore, 0, "afking box stamped (non-vacuous)");

        // Open the HUMAN box path. It must NOT touch the afking sub's stamp.
        vm.prank(makeAddr("human_opener"));
        game.openBoxes(50);
        assertEq(_lastBoughtDayOf(afk), afkBoughtBefore, "human open did not mutate the afking stamp (lastAutoBoughtDay)");
        assertEq(_lastOpenedDayOf(afk), afkOpenedBefore, "human open did not open the afking box (lastOpenedDay unchanged)");

        // Now open the AFKING box path (mintFlip open leg). It materializes the afking box; the human
        // path's already-opened state is independent.
        vm.prank(makeAddr("afk_opener"));
        try game.mintFlip() {} catch {}
        // The afking box opened iff lastOpenedDay advanced to lastAutoBoughtDay (the open marker).
        assertEq(_lastOpenedDayOf(afk), afkBoughtBefore, "afking open materialized the afking box (lastOpenedDay == lastAutoBoughtDay)");
    }

    // =========================================================================
    // (b) NO-ORPHAN — a sub removed between stamp and open gets NO free box
    // =========================================================================

    /// @notice NO-ORPHAN control: a stamped, in-set sub IS opened by the afking open leg (the box
    ///         materializes). This is the non-vacuity anchor for the orphan assertions below.
    function testNoOrphanControlInSetSubOpens() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        address p = makeAddr("orphan_control");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);
        _fundPool(p, 5 ether);
        _runStageNewDay(0xCC01);

        uint32 stampDay = _lastBoughtDayOf(p);
        assertGt(stampDay, 0, "box stamped");
        assertTrue(_lastOpenedDayOf(p) < stampDay, "box pending (lastOpenedDay < lastAutoBoughtDay)");

        _settleGame(0xCC02);
        vm.prank(makeAddr("control_opener"));
        try game.mintFlip() {} catch {}

        // In-set + stamped -> the box OPENS (the control: a box WOULD materialize).
        assertEq(_lastOpenedDayOf(p), stampDay, "in-set sub's box opened (control materializes)");
    }

    /// @notice NO-ORPHAN: a sub REMOVED from `_subscribers` between stamp and open gets NO free box —
    ///         the afking open leg walks `_subscribers` and never reaches it, so the paid-for box is
    ///         never materialized (the orphan condition). Asserted NON-VACUOUSLY against the control
    ///         above (the same stamp WOULD have opened if the sub stayed in-set).
    function testNoOrphanRemovedSubGetsNoBox() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        address p = makeAddr("orphan_removed");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);
        _fundPool(p, 5 ether);
        _runStageNewDay(0xCD01);

        uint32 stampDay = _lastBoughtDayOf(p);
        assertGt(stampDay, 0, "box stamped");
        assertTrue(_lastOpenedDayOf(p) < stampDay, "box pending pre-open");

        // Remove the sub from `_subscribers` between stamp and open (the orphan condition). The afking
        // open leg walks `_subscribers`, so a removed sub is never reached.
        _forceRemoveFromSubscribers(p);
        assertEq(_subscriberIndexOf(p), 0, "sub removed from _subscribers (orphan condition)");

        _settleGame(0xCD02);
        vm.prank(makeAddr("orphan_opener"));
        try game.mintFlip() {} catch {}

        // ORPHAN: the box was NEVER materialized — lastOpenedDay stayed < lastAutoBoughtDay (no free box).
        assertTrue(_lastOpenedDayOf(p) < stampDay, "NO-ORPHAN: removed sub's box never materialized (no free box)");
    }

    /// @notice NO-ORPHAN guard dominates the cancel-reclaim path: a sub with a PENDING box that is
    ///         cancelled (tombstone) is NOT reclaimed by the next STAGE (the :570 guard leaves it
    ///         untouched), so its box is preserved for the open leg — the contract itself NEVER orphans
    ///         a pending-box sub via the STAGE.
    function testNoOrphanGuardLeavesPendingBoxSubUntouchedByStage() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        address p = makeAddr("orphan_guard");
        _grantDeityPass(p);
        _subscribeLootbox(p, 1);
        _fundPool(p, 5 ether);
        _runStageNewDay(0xCE01);

        uint32 stampDay = _lastBoughtDayOf(p);
        assertTrue(_lastOpenedDayOf(p) < stampDay, "box pending");

        // Cancel the sub (tombstone). A normal tombstone is reclaimed by the next STAGE — but the
        // NO-ORPHAN guard leaves a PENDING-box sub untouched (no reclaim while a box is unopened).
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, address(0)); // tombstone
        assertEq(_dailyQtyOf(p), 0, "tombstoned");

        vm.recordLogs();
        _runStageNewDay(0xCE02);
        _drainLogs();

        // The NO-ORPHAN guard dominated: the pending-box sub was NOT reclaimed this cycle (still in set,
        // no CancelReclaim emitted), so its paid-for box survives.
        assertEq(_countExpiredFor(p, 2), 0, "NO-ORPHAN guard: pending-box tombstone NOT reclaimed this cycle");
        assertGt(_subscriberIndexOf(p), 0, "pending-box sub stays in set (box preserved for the open leg)");
    }

    // =========================================================================
    // (c) Streak-preserved swap-pop (scorePlus1 survives the tombstone-reclaim)
    // =========================================================================

    /// @notice The swap-pop does NOT corrupt the surviving mover's mint-streak score. In v55 the STAGE
    ///         re-derives `scorePlus1 = _playerActivityScore(player, streak, ...) + 1` per fresh buy
    ///         (GameAfkingModule.sol:785-793) — a genuinely-per-sub value. The property TST-04 regresses
    ///         is that the swap-pop RELOCATION (the mover taking the cancelled sub's freed slot) does not
    ///         alter the mover's own streak-derived score and does not leak the cancelled sub's state:
    ///         the cancelled sub's record is fully DELETED (scorePlus1 == 0), and the displaced mover
    ///         gets EXACTLY the same scorePlus1 as an identically-situated control sub that was NEVER
    ///         displaced. Non-vacuous: the control proves the expected score is non-zero and well-defined.
    function testStreakNotCorruptedBySwapPop() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        // ONE fresh fixture, all subs subscribed before any STAGE buy (no pending boxes, so the
        // NO-ORPHAN guard does not protect the tombstone from reclaim). subs[0] is tombstoned and
        // swap-popped; the tail `mover` is displaced into its slot; an UNDISPLACED `ctrl` sub with the
        // identical activity is the byte-identical reference.
        address ctrl = makeAddr("streak_ctrl");
        uint256 N = 3;
        address[] memory subs = new address[](N);
        // Subscribe ctrl first (a stable mid-set member that is never displaced).
        _grantDeityPass(ctrl);
        _subscribeLootbox(ctrl, 1);
        _fundPool(ctrl, 5 ether);
        for (uint256 i; i < N; i++) {
            address w = makeAddr(string(abi.encodePacked("streak_disp_", _u(i))));
            subs[i] = w;
            _grantDeityPass(w);
            _subscribeLootbox(w, 1);
            _fundPool(w, 5 ether);
        }
        address mover = subs[N - 1];
        // Pre-set GARBAGE scorePlus1 on the mover to prove the swap-pop does not leak it through (the
        // fresh buy must overwrite it with the correctly-derived value, byte-identical to ctrl).
        _setScorePlus1(mover, 0xBEEF);

        // Tombstone the FIRST displaced sub so the tail `mover` swap-pops into its slot during the
        // STAGE reclaim (no prior buy -> no pending box -> the reclaim fires).
        vm.prank(subs[0]);
        game.subscribe(address(0), false, false, 0, address(0));
        assertEq(_dailyQtyOf(subs[0]), 0, "first displaced sub tombstoned");

        vm.recordLogs();
        _runStageNewDay(0x57D1);
        _drainLogs();

        // The cancelled sub's record is FULLY DELETED (no streak-state leak).
        assertEq(_countExpiredFor(subs[0], 2), 1, "tombstone reclaimed (swap-pop fired)");
        assertEq(_subscriberIndexOf(subs[0]), 0, "tombstone removed from set");
        assertEq(_scorePlus1Of(subs[0]), 0, "cancelled sub's record fully deleted (scorePlus1 == 0)");

        // The undisplaced control was processed this same STAGE with a well-defined, non-zero score.
        uint16 ctrlScore = _scorePlus1Of(ctrl);
        assertGt(ctrlScore, 0, "control: a fresh buy derives a non-zero scorePlus1 (well-defined)");
        assertGt(_lastBoughtDayOf(ctrl), 0, "control processed this STAGE");

        // STREAK NOT CORRUPTED: the displaced mover, processed this pass, gets EXACTLY the control's
        // scorePlus1 — the swap-pop relocation neither reset it nor leaked the 0xBEEF garbage / the
        // cancelled sub's state. Byte-identical to a never-displaced sub with the same activity.
        assertGt(_lastBoughtDayOf(mover), 0, "displaced mover processed this pass (no cursor-skip)");
        assertEq(
            _scorePlus1Of(mover),
            ctrlScore,
            "swap-pop did not corrupt the mover's mint-streak score (byte-identical to the undisplaced control)"
        );
    }

    // =========================================================================
    // (d) OPEN-E 4-protection regression
    // =========================================================================

    /// @notice OPEN-E (1) consent-gate-at-subscribe: subscribing with an UNAPPROVED non-zero non-self
    ///         fundingSource REVERTS NotApproved at subscribe (the gate is checked HERE only).
    function testOpenEConsentGateUnapprovedReverts() public {
        address s = makeAddr("openE_s");
        address m = makeAddr("openE_m");
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.subscribe(address(0), false, true, 1, s); // S has not approved M -> REVERT
    }

    /// @notice OPEN-E (2) default-self byte-identical: subscribe with fundingSource = address(0) stores
    ///         `_fundingSourceOf == address(0)` and resolves the funder as `self` — the deposit + draw
    ///         both key on the subscriber's own afkingFunding bucket (byte-identical to the single-account
    ///         flow).
    function testOpenEDefaultSelfByteIdentical() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        address m = makeAddr("self_m");
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, address(0)); // self-funded
        assertEq(_fundingSourceOf(m), address(0), "default-self: _fundingSourceOf == address(0)");

        // A deposit to self credits the subscriber's own bucket (the draw debits the same bucket).
        _fundPool(m, 1 ether);
        assertEq(game.afkingFundingOf(m), 1 ether, "default-self: the subscriber's own bucket is funded");
    }

    /// @notice OPEN-E (3) no-escalation: the fundingSource is fixed at subscribe — an operator cannot
    ///         widen the grant per-draw. Re-pointing the source IS a re-subscribe, which RE-RUNS the
    ///         consent gate. Proves an operator-funded sub cannot be re-pointed to a NEW unapproved
    ///         source without the new source's consent.
    function testOpenENoEscalation() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        address s = makeAddr("noesc_s");
        address m = makeAddr("noesc_m");
        address s2 = makeAddr("noesc_s2"); // a SECOND source that never approves M
        vm.prank(s);
        game.setOperatorApproval(m, true);
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, s); // honored: source = S
        assertEq(_fundingSourceOf(m), s, "initial source = S");

        // Attempt to RE-POINT the source to S2 (which never approved M) — the re-subscribe RE-RUNS the
        // consent gate and REVERTS (no escalation to an unapproved source).
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.subscribe(address(0), false, true, 1, s2);
        // The source is unchanged (the failed re-point did not escalate).
        assertEq(_fundingSourceOf(m), s, "no-escalation: source unchanged after the rejected re-point");
    }

    /// @notice OPEN-E (4) trust-the-sub temporal bound: after S approves M and M subscribes with
    ///         fundingSource = S, S REVOKES the approval. The active sub is NOT terminated by the revoke
    ///         (the gate is subscribe-time only; the per-draw path never re-checks) — the sub is the
    ///         consent unit (stop = M cancels or S defunds).
    function testOpenETrustTheSubRevokeDoesNotStop() public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        address s = makeAddr("trust_s");
        address m = makeAddr("trust_m");
        vm.prank(s);
        game.setOperatorApproval(m, true);
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, s);
        assertGt(_subscriberIndexOf(m), 0, "M's sub active");

        // S REVOKES after the sub is active.
        vm.prank(s);
        game.setOperatorApproval(m, false);
        assertFalse(game.isOperatorApproved(s, m), "S revoked M");

        // The active sub is NOT terminated by the revoke; the stored source is unchanged.
        assertGt(_subscriberIndexOf(m), 0, "trust-the-sub: active sub NOT stopped by the revoke");
        assertEq(_fundingSourceOf(m), s, "trust-the-sub: stored source unchanged (no per-draw re-check)");
    }

    /// @notice OPEN-E fuzz (D-351-04): over random subscribe / evict / swap-pop ORDERINGS the set stays
    ///         membership-consistent and the default-self funder resolution is byte-identical for every
    ///         self-funded sub (the funder == self invariant holds regardless of ordering).
    function testFuzzOpenEDefaultSelfHoldsUnderOrderings(uint8 ordering) public {
        vm.skip(true, "357-00b D-12 supersession: the v55 set-mutation/OPEN-E harness subscribes an ungrounded sub then exercises the no-orphan/swap-pop/OPEN-E STAGE; the grounded subscribe stamps a no-orphan-protected box at subscribe; re-proven by V56SecUnmanipulable (no-orphan + finalize hooks) + V56SubHardening (D-13 exemption + crossing eviction)");
        uint256 N = 5;
        address[] memory subs = new address[](N);
        for (uint256 i; i < N; i++) {
            address w = makeAddr(string(abi.encodePacked("ord_", _u(i))));
            subs[i] = w;
            _grantDeityPass(w);
            vm.prank(w);
            game.subscribe(address(0), false, true, 1, address(0)); // self-funded
            _fundPool(w, 1 ether);
        }
        // Random cancel subset (the swap-pop orderings).
        for (uint256 i; i < N; i++) {
            if ((ordering >> i) & 1 == 1) {
                vm.prank(subs[i]);
                game.subscribe(address(0), false, true, 0, address(0)); // tombstone
            }
        }
        vm.recordLogs();
        _runStageNewDay(uint256(keccak256(abi.encode(ordering))) & 0xFFFFFF);
        _drainLogs();

        // Every surviving self-funded sub kept funder == self (default-self byte-identical), and every
        // cancelled sub was reclaimed out (membership-consistent) regardless of the ordering.
        for (uint256 i; i < N; i++) {
            if ((ordering >> i) & 1 == 1) {
                assertEq(_subscriberIndexOf(subs[i]), 0, "cancelled sub reclaimed out of set");
            } else {
                assertEq(_fundingSourceOf(subs[i]), address(0), "survivor: default-self funder == self (byte-identical)");
                assertGt(_subscriberIndexOf(subs[i]), 0, "survivor stays in set");
            }
        }
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Drive the per-sub buy STAGE for a NEW day (Δ4 successor to afKing.autoBuy): warp +1 day,
    ///      settle so processSubscriberStage(SUB_STAGE_BATCH) stamps the funded set + the day word lands.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Settle the game to a clean state (PATTERNS §"Settle-to-clean-state VRF drain").
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Forcibly remove `who` from `_subscribers` (the orphan condition): zero its
    ///      `_subscriberIndex` and shrink the array length by 1 (a test-only simulation of a removal
    ///      between stamp and open; the contract's own STAGE never does this to a pending-box sub).
    function _forceRemoveFromSubscribers(address who) internal {
        uint256 idxPlus1 = _subscriberIndexOf(who);
        if (idxPlus1 == 0) return;
        uint256 idx = idxPlus1 - 1;
        bytes32 lenSlot = bytes32(uint256(SUBSCRIBERS_SLOT));
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        // Swap-pop: move the last element into `idx`, fix its index, shrink length, clear `who`'s index.
        if (idx != len - 1) {
            address mover = address(uint160(uint256(vm.load(address(game), bytes32(uint256(dataBase) + (len - 1))))));
            vm.store(address(game), bytes32(uint256(dataBase) + idx), bytes32(uint256(uint160(mover))));
            vm.store(address(game), keccak256(abi.encode(mover, uint256(SUBSCRIBER_INDEX_SLOT))), bytes32(idxPlus1));
        }
        vm.store(address(game), lenSlot, bytes32(len - 1));
        vm.store(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT))), bytes32(uint256(0)));
    }

    // ---- Sub field reads (RE-DERIVED slot 54 + verified offsets) ----

    function _subSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), _subSlot(who))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _scorePlus1Of(address who) internal view returns (uint16) {
        return uint16(_subField(who, OFF_SCOREPLUS1, 16));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    /// @dev Pin `who`'s scorePlus1 (bytes 6..7) — the mint-streak EV input.
    function _setScorePlus1(address who, uint16 score) internal {
        bytes32 slot = _subSlot(who);
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFF) << (OFF_SCOREPLUS1 * 8));
        packed |= (uint256(score) << (OFF_SCOREPLUS1 * 8));
        vm.store(address(game), slot, bytes32(packed));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    function _fundingSourceOf(address who) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(54)))))));
    }

    // ---- Event drain (emitter == address(game) — the game-resident module emits via delegatecall) ----

    function _drainLogs() internal {
        delete _expiredPlayers;
        delete _expiredReasons;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) {
                _expiredPlayers.push(address(uint160(uint256(logs[i].topics[1]))));
                _expiredReasons.push(uint8(uint256(bytes32(logs[i].data))));
            }
        }
    }

    function _countExpiredFor(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _expiredPlayers.length; i++) {
            if (_expiredPlayers[i] == who && _expiredReasons[i] == reason) count++;
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
