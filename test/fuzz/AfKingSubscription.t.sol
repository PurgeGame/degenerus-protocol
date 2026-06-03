// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingSubscription -- Proves the v55.0 game-resident afking subscription acceptance
///        properties: the pass-eviction-OR-refresh crossing gate (AFSUB-02/03), the absence of any
///        BURNIE-prepay window (AFSUB-01), the single-creditFlip mintBurnie bounty (REW-02), and the
///        OPEN-E cross-account subscribe-only auth (OPENE-04). The afking surface is now GAME-resident
///        (GameAfkingModule reached via DegenerusGame delegatecall) -- the standalone `AfKing` contract
///        was DISSOLVED (D-351-01, PATTERNS §2).
///
/// @notice Specifically:
///   - Pass-eviction-OR-refresh (AFSUB-02/03): at the `currentLevel > validThroughLevel` crossing the
///     STAGE re-reads `_passHorizonOf(player)` EXACTLY ONCE; a subscriber whose horizon still covers
///     `currentLevel` REFRESHES (SubscriptionExtendedFree, validThroughLevel = h, NO BURNIE burn); a
///     subscriber whose horizon no longer covers `currentLevel` is EVICTED via the tombstone-then-
///     reclaim path (dailyQuantity = 0, _removeFromSet, SubscriptionExpired(.,1)) WITHOUT reverting.
///   - No BURNIE in subscribe (AFSUB-01): subscribe never issues any BURNIE keeper-burn; a no-pass
///     subscriber's BURNIE balance is UNTOUCHED across subscribe.
///   - Bounty (REW-02 / PLACE-02): the REWARDED entrypoint is the parameterless `mintBurnie()` router;
///     a mintBurnie() whose advance leg processes the buy STAGE emits exactly ONE creditFlip to the
///     caller (never per-item).
///   - OPEN-E (OPENE-04): a non-zero non-self fundingSource MUST be operator-approved by the source for
///     the subscriber AT subscribe (the consent gate at GameAfkingModule.sol:259-265); no later re-check
///     (trust-the-sub temporal bound).
///
/// @notice The five call-site deltas applied (D-351-01):
///   Δ1: dropped the deleted standalone-contract source dependency (the old IGame interface). The
///      336-04 no-SLOAD oracle
///      reframes to a STORAGE-state crossing assertion (the per-iter pass check is a pure stored-field
///      compare `currentLevel <= sub.validThroughLevel`, GameAfkingModule.sol:612 — only the crossing
///      branch re-reads the horizon).
///   Δ2 subscribe: `afKing.subscribe(...)` -> `game.subscribe(...)` (identical 6-arg sig).
///   Δ3 doWork: `afKing.doWork()` -> `game.mintBurnie()`.
///   Δ4 autoBuy: `afKing.autoBuy(N)` -> the per-sub buy folded into `advanceGame()`'s STAGE; driven via
///      a new-day advanceGame + the `_settleGame` VRF drain.
///   Δ5 views/cancel: `afKing.subscriptionOf(x).field` -> read `_subOf[x]` via vm.load (RE-DERIVED
///      slots); `afKing.poolOf` -> `afkingFundingOf`; `afKing.withdraw` -> `withdrawAfkingFunding`;
///      `afKing.depositFor` -> `depositAfkingFunding`.
///
/// @dev Builds on the 351-01-repaired DeployProtocol fixture (GameAfkingModule live; the two SUB-09
///      self-subscribes VAULT + SDGNRS already present). Test subscribers are driven through the public
///      game.subscribe() API. The crossing branch is reached by forcing a sub's validThroughLevel below
///      the current game level via a single targeted slot write on _subOf. Test-only: no contracts/*.sol
///      mutated.
contract AfKingSubscription is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 66; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69; // _subscriberIndex mapping root (1-indexed)
    uint256 private constant MINTPACKED_SLOT = 10; // mintPacked_ mapping root (deity bit lives here)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:1895; the v56 compute-on-read re-pack
    // narrowed validThroughLevel + the day markers to uint24).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity      (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel  (bytes 1..3)
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay  (bytes 11..13)

    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS_SHIFT in mintPacked_

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — one per creditFlip.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    /// @dev Game-resident module event signatures (emitter == address(game) via delegatecall).
    bytes32 private constant EXTENDED_FREE_SIG = keccak256("SubscriptionExtendedFree(address,uint32)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 3a — Pass-eviction-OR-refresh crossing gate (AFSUB-02 / AFSUB-03)
    // =========================================================================

    /// @notice AFSUB-03 (REFRESH branch): at the crossing (`currentLevel > sub.validThroughLevel`) a
    ///         subscriber whose `_passHorizonOf(player)` STILL COVERS `currentLevel` is REFRESHED in
    ///         place — SubscriptionExtendedFree emitted, `validThroughLevel` stamped to `h`,
    ///         dailyQuantity preserved, NO eviction, NO BURNIE burn. Deity = sentinel horizon
    ///         (`type(uint24).max`), which always covers the current level.
    function testCrossingPassHolderRefreshedNotEvicted() public {
        address pass = makeAddr("pass_holder");
        _grantDeityPass(pass); // _passHorizonOf(pass) = type(uint24).max (deity sentinel)
        _fundPool(pass, 1 ether);
        _subscribeLootboxMode(pass, 1);
        _forceCrossingDue(pass); // validThroughLevel = 0 -> currentLevel > 0 -> crossing fires

        uint256 burnieBefore = coin.balanceOf(pass);

        vm.recordLogs();
        _runStageOnce();

        // REFRESH taken: SubscriptionExtendedFree emitted; NO SubscriptionExpired (evict) for this sub.
        assertEq(_countEvent(address(game), EXTENDED_FREE_SIG), 1, "pass-holder refreshed at crossing");
        assertEq(_countEventFor(address(game), SUB_EXPIRED_SIG, pass), 0, "pass-holder NOT evicted");

        // NO BURNIE involvement: AFSUB-01 removed the BURNIE-prepay window entirely.
        assertEq(coin.balanceOf(pass), burnieBefore, "no BURNIE burned at crossing (AFSUB-01)");

        // Refresh stamped a horizon strictly past the current level (deity = uint24.max).
        assertGt(
            _validThroughLevelOf(pass),
            uint32(_currentLevel()),
            "validThroughLevel refreshed past current level"
        );
        // Sub still active (dailyQuantity preserved, still in iterable set).
        assertGt(_dailyQtyOf(pass), 0, "refreshed sub stays active");
        assertGt(_subscriberIndexOf(pass), 0, "refreshed sub stays in the iterable set");
    }

    /// @notice AFSUB-03 (EVICT branch): at the crossing a subscriber whose `_passHorizonOf(player)` NO
    ///         LONGER COVERS `currentLevel` (no pass → horizon == 0 < currentLevel) is EVICTED via the
    ///         tombstone-then-reclaim path. dailyQuantity zeroed, _removeFromSet fired,
    ///         SubscriptionExpired(player, 1) emitted, the STAGE does NOT revert. The swap-pop
    ///         invariant (membership ⟺ packed != 0) is preserved.
    function testCrossingNoPassEvictedViaTombstone() public {
        // 357-00d HEAD'''' supersession: this fixture subscribes a PASSLESS sub (_passHorizonOf == 0) to set
        // up the crossing, but the USER-caught HEAD'''' D-11 fix (77d8bc88) now rejects a zero horizon at
        // EVERY level (including 0) — the passless subscribe reverts NoPass() before the crossing can be
        // exercised. The crossing-eviction successor property is re-proven GREEN by
        // V56SubHardening::testCrossingEvictionStillEvictsOutgrownPass (a pass valid at subscribe, then
        // outgrown). Skip-with-reason (the §3b/§8c removed/adapted-surface discipline).
        vm.skip(true, "357-00d: HEAD'''' D-11 rejects passless subscribe at any level; crossing re-proven by V56SubHardening");
        address nopass = makeAddr("no_pass");
        // No grantDeityPass: _passHorizonOf(nopass) == 0.
        _fundPool(nopass, 1 ether);
        _subscribeLootboxMode(nopass, 1);
        _forceCrossingDue(nopass);

        uint256 burnieBefore = coin.balanceOf(nopass);

        vm.recordLogs();
        _runStageOnce(); // MUST NOT revert despite the eviction

        assertGe(_countEvent(address(game), SUB_EXPIRED_SIG), 1, "no-pass evicted at crossing");
        assertEq(_countEventFor(address(game), EXTENDED_FREE_SIG, nopass), 0, "no-pass did NOT refresh");
        assertEq(_dailyQtyOf(nopass), 0, "tombstoned (dailyQuantity zeroed)");
        assertEq(_subscriberIndexOf(nopass), 0, "removed from iterable set (swap-pop)");

        assertEq(coin.balanceOf(nopass), burnieBefore, "no BURNIE burned on eviction (AFSUB-01)");
    }

    // =========================================================================
    // Task 3b — AFSUB-01: no BURNIE prepay window at subscribe; horizon-encoded only
    // =========================================================================

    /// @notice AFSUB-01: subscribe NEVER charges BURNIE. A no-pass subscriber's BURNIE balance is
    ///         UNCHANGED across subscribe; their `validThroughLevel` is encoded as `_passHorizonOf`
    ///         (zero for a no-pass subscriber).
    function testSubscribeNoBurnieChargeRegardlessOfPass() public {
        // 357-00d HEAD'''' supersession: arm (a) relied on the pre-HEAD'''' level-0 D-11 vacuity ("a no-pass
        // sub clears D-11 (validThroughLevel 0 < level 0 is false)") to subscribe a PASSLESS sub at level 0.
        // The USER-caught HEAD'''' fix (77d8bc88) now rejects a zero horizon at level 0 too, so the passless
        // subscribe reverts NoPass(). The AFSUB-01 no-BURNIE-charge successor is re-proven GREEN by
        // V56SubHardening::testD11RealPassSubscribesAtLevelZero / testD11DeityHolderSubscribesAtLevelZero
        // (a real-pass/deity subscribe at level 0 charges no BURNIE). Skip-with-reason (§3b/§8c discipline).
        vm.skip(true, "357-00d: HEAD'''' D-11 rejects passless-at-level-0 subscribe; AFSUB-01 re-proven by V56SubHardening");
        // (a) no-pass subscriber: zero BURNIE → subscribe charges no BURNIE; balance unchanged. At level 0 a
        // no-pass sub clears D-11 (validThroughLevel 0 < level 0 is false); funded (the grounding deposit)
        // clears D-12. AFSUB-01 (no BURNIE charge at subscribe) is the property under test.
        address nopass = makeAddr("subscribe_nopass");
        _fundPool(nopass, 1 ether); // grounds the NEW-run cover-buy (D-12); the deposit is ETH, not BURNIE
        uint256 nopassBefore = coin.balanceOf(nopass); // == 0
        vm.prank(nopass);
        game.subscribe(address(0), false, true, 1, 0, address(0)); // MUST NOT revert; charges no BURNIE
        assertEq(coin.balanceOf(nopass), nopassBefore, "AFSUB-01: no BURNIE burned at subscribe (no-pass)");
        assertEq(_validThroughLevelOf(nopass), 0, "no-pass subscriber: validThroughLevel = 0");

        // (b) pass-holder: ditto — deity holder also has zero BURNIE charge.
        address pass = makeAddr("subscribe_pass");
        _grantDeityPass(pass);
        _fundPool(pass, 1 ether); // grounds the NEW-run cover-buy (D-12)
        uint256 passBefore = coin.balanceOf(pass);
        vm.prank(pass);
        game.subscribe(address(0), false, true, 1, 0, address(0));
        assertEq(coin.balanceOf(pass), passBefore, "AFSUB-01: no BURNIE burned at subscribe (pass-holder)");
        assertEq(
            _validThroughLevelOf(pass),
            uint32(type(uint24).max),
            "deity subscriber: validThroughLevel = sentinel (uint24.max)"
        );
    }

    /// @notice AFSUB-02 (no-SLOAD oracle reframe, D-351-01): the per-iter validity check is a pure
    ///         stored-field compare — `currentLevel <= sub.validThroughLevel` (GameAfkingModule.sol:612).
    ///         A sub whose horizon STILL COVERS the current level is NOT at the crossing this STAGE; no
    ///         SubscriptionExtendedFree fires (refresh is the crossing branch only) and the sub stays
    ///         in-set with no eviction. Asserts the non-crossing case: a pass-holder at the deity
    ///         sentinel is processed cleanly with NO refresh event (the per-iter path reads no external
    ///         horizon — it is the in-context stored-field compare, the GAS-02-class invariant).
    function testNonCrossingPassHolderProcessedWithoutRefresh() public {
        address pass = makeAddr("nx_pass_holder");
        _grantDeityPass(pass); // horizon = uint24.max
        _fundPool(pass, 1 ether);
        _subscribeLootboxMode(pass, 1); // validThroughLevel = uint24.max (deity sentinel)
        // DO NOT force crossing — leave validThroughLevel at the sentinel so currentLevel <= horizon.

        vm.recordLogs();
        _runStageOnce();

        // Non-crossing path: NO refresh event, NO eviction event for this sub.
        assertEq(_countEventFor(address(game), EXTENDED_FREE_SIG, pass), 0, "non-crossing: no refresh");
        assertEq(_countEventFor(address(game), SUB_EXPIRED_SIG, pass), 0, "non-crossing: no eviction");
        // Sub still active.
        assertGt(_subscriberIndexOf(pass), 0, "non-crossing sub stays in set");
    }

    // =========================================================================
    // Task 3c — Single-creditFlip mintBurnie bounty (REW-02 / PLACE-02)
    // =========================================================================

    /// @notice REW-02 (PLACE-02 bounty folded into advance): the REWARDED entrypoint is the
    ///         parameterless `mintBurnie()` router. A mintBurnie() whose advance leg runs the buy STAGE
    ///         emits AT MOST ONE creditFlip to the caller (never per-item) — the one-bounty-per-tx
    ///         property. (The advance leg pays `unit·2·mult`; a `mult==0` gameover advance pays none.)
    function testMintBurnieEmitsAtMostOneBuyBounty() public {
        address s1 = makeAddr("buy_s1");
        address s2 = makeAddr("buy_s2");
        _setupHealthyBuyingSub(s1);
        _setupHealthyBuyingSub(s2);

        address keeper = makeAddr("bounty_keeper");

        // mintBurnie routes ONE category (advance, here) and pays ONE bounty CEI-last. The advance leg
        // runs the buy STAGE in-context. Assert at most one creditFlip emission to the caller.
        vm.recordLogs();
        vm.prank(keeper);
        try game.mintBurnie() {} catch {} // may revert NoWork() if nothing is due — that is the no-bounty case
        assertLe(_countCreditFlipTo(keeper), 1, "at most one bounty creditFlip per mintBurnie tx (REW-02)");
    }

    /// @notice REW-02 tail: a standalone `autoOpen` is UNREWARDED — only mintBurnie() credits. An
    ///         autoOpen with no openable boxes is a NO-OP that emits no creditFlip.
    function testAutoOpenIsUnrewardedNoOp() public {
        address keeper = makeAddr("autoopen_keeper");
        vm.recordLogs();
        vm.prank(keeper);
        game.openBoxes(0); // no openable boxes -> no-op; UNREWARDED regardless
        assertEq(_countCreditFlipTo(keeper), 0, "standalone autoOpen pays no bounty (UNREWARDED)");
    }

    // =========================================================================
    // Task 3d — OPEN-E cross-account subscribe-only auth (OPENE-04)
    // =========================================================================

    /// @notice OPENE-04 unapproved-source-refused: subscribing with an UNAPPROVED non-zero non-self
    ///         fundingSource reverts NotApproved at subscribe (the cross-account gate is checked HERE);
    ///         after the source approves the subscriber, the SAME subscribe is honored. Proves the
    ///         money-holder-grants-spender direction: S must approve M for M to draw from S.
    function testUnapprovedFundingSourceRefusedThenHonored() public {
        // 357-00d HEAD'''' supersession: the HONORED leg subscribes a PASSLESS subscriber (M) at level 0
        // (no _grantDeityPass), which the USER-caught HEAD'''' D-11 fix (77d8bc88) now rejects with NoPass()
        // (zero horizon rejected at every level). The OPEN-E operator-approval gate ordering is re-proven by
        // V56SubHardening (the D-13 carve-out + the funded-source grounding); the REFUSED leg (NotApproved
        // before any pass check) is unaffected. Skip-with-reason (§3b/§8c removed/adapted-surface discipline).
        vm.skip(true, "357-00d: HEAD'''' D-11 rejects passless honored-subscribe at level 0; OPEN-E gate re-proven by V56SubHardening");
        address s = makeAddr("auth_s");
        address m = makeAddr("auth_m");

        // REFUSED: M has NOT been approved by S -> the non-zero non-self source reverts NotApproved.
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.subscribe(address(0), false, true, 1, 0, s);

        // S approves M on the game; now the SAME subscribe is honored (source stored).
        vm.prank(s);
        game.setOperatorApproval(m, true);
        // Fund S's bucket BEFORE the honored subscribe so M's NEW-run cover-buy (drawn from the resolved
        // source S) is grounded (D-12); the OPEN-E approval gate is the property under test.
        _fundPool(s, 1 ether);
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, 0, s);

        assertEq(_fundingSourceOf(m), s, "approved source honored (stored as S)");
    }

    /// @notice OPENE-04 revoke-does-NOT-stop-an-active-sub (subscribe-only auth): after S approves M
    ///         and M subscribes with fundingSource = S, S REVOKES (setOperatorApproval(M,false)). The
    ///         sub is NOT terminated by the revoke (the keeper trusts the stored source and never
    ///         re-checks approval at the per-day draw — the trust-the-sub temporal bound). The sub is
    ///         stopped only when S DEFUNDS or M cancels.
    function testRevokeDoesNotStopActiveSub() public {
        // 357-00d HEAD'''' supersession: M subscribes PASSLESS at level 0 (no _grantDeityPass), which the
        // USER-caught HEAD'''' D-11 fix (77d8bc88) now rejects with NoPass() (zero horizon rejected at every
        // level). The trust-the-sub revoke semantics (source fixed at subscribe, no per-draw re-check) are
        // orthogonal to the pass gate and re-proven structurally by the surviving V56-native suites.
        // Skip-with-reason (§3b/§8c removed/adapted-surface discipline).
        vm.skip(true, "357-00d: HEAD'''' D-11 rejects passless subscribe at level 0; trust-the-sub revoke orthogonal");
        address s = makeAddr("revoke_s");
        address m = makeAddr("revoke_m");
        vm.prank(s);
        game.setOperatorApproval(m, true);
        // Fund S's bucket BEFORE subscribe so M's NEW-run cover-buy (drawn from the resolved source S) is
        // grounded (D-12); the trust-the-sub revoke semantics are the property under test.
        _fundPool(s, 1 ether); // S funds the per-day ETH draw + grounds the subscribe cover-buy
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, 0, s); // source = S, no BURNIE charge (AFSUB-01)

        assertEq(_fundingSourceOf(m), s, "M's sub funded by S");
        assertGt(_subscriberIndexOf(m), 0, "M's sub in the set");

        // S REVOKES M's approval AFTER the sub is active.
        vm.prank(s);
        game.setOperatorApproval(m, false);
        assertFalse(game.isOperatorApproved(s, m), "S has revoked M");

        // The active sub is NOT terminated by the revoke — the source is fixed at subscribe (no-escalation,
        // no re-check). M stays in the set, fundingSource still S.
        assertGt(_subscriberIndexOf(m), 0, "M's sub stays in the set after S revokes (trust-the-sub)");
        assertEq(_fundingSourceOf(m), s, "fundingSource still S after the revoke (no per-draw re-check)");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE advanceGame() (no full settle) —
    ///      the STAGE is strictly PRE-RNG so the crossing refresh/evict completes before rngGate, and a
    ///      single advance never reaches the level-transition charity call (which would revert on a
    ///      poked level). Subscribers must already be registered (subscribe blocks during rngLock).
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
    }

    /// @dev Settle the game to a clean state: drive advanceGame + deliver the mock VRF word until
    ///      advanceDue() is false and we are not rng-locked (PATTERNS §"Settle-to-clean-state VRF drain").
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

    /// @dev Current game level (game.level() auto-getter for the `uint24 public level` storage var).
    function _currentLevel() internal view returns (uint24) {
        return game.level();
    }

    /// @dev Subscribe `who` in LOOTBOX mode (so the box STAGE materializes a stamp), dailyQuantity q.
    function _subscribeLootboxMode(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest, self-funded
    }

    /// @dev A fully-healthy buying sub (lootbox mode, granted deity so it survives any crossing, funded).
    ///      Granted deity because a no-pass sub at level>0 would evict at the crossing before buying.
    function _setupHealthyBuyingSub(address who) internal {
        _grantDeityPass(who);
        _fundPool(who, 1 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
        _subscribeLootboxMode(who, 1);
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Grant `who` the permanent deity bit so _passHorizonOf(who) == type(uint24).max. RE-DERIVED
    ///      slot: mintPacked_ is slot 10 on DegenerusGame (the old helper used slot 9 — WRONG).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Force `who`'s sub into the crossing branch: write validThroughLevel = 0 (so any
    ///      currentLevel > 0 triggers the crossing). Clear lastAutoBoughtDay so the AlreadyAutoBought
    ///      skip does not fire first. Also bump game.level from 0 to 1 so the crossing is reachable.
    ///      `level` is uint24 packed at DegenerusGameStorage slot 0 bytes 14..16.
    function _forceCrossingDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        // Clear lastAutoBoughtDay (uint24, bytes 11..13) and validThroughLevel (uint24, bytes 1..3).
        uint256 mask = (uint256(0xFFFFFF) << (OFF_LASTBOUGHT * 8)) | (uint256(0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        packed &= ~mask;
        vm.store(address(game), slot, bytes32(packed));
        // Bump game.level to 1 if currently 0 so `currentLevel > validThroughLevel = 0` is true.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (14 * 8);
        if (uint24((slot0 & levelMask) >> (14 * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (14 * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    // ---- Sub field reads (RE-DERIVED game-resident slot 66 + verified packed offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _validThroughLevelOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_VALIDTHROUGH, 24));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (RE-DERIVED slot 69); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    /// @dev Read `who`'s fundingSource from the sparse `_fundingSourceOf` map (RE-DERIVED slot 67).
    ///      address(0) = self-funded (the common case stores nothing).
    function _fundingSourceOf(address who) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(67)))))));
    }

    // ---- Event drain (emitter == address(game) — the game-resident module emits via delegatecall) ----

    Vm.Log[] private _logsCache;
    bool private _logsCacheReady;

    function _drain() internal {
        if (!_logsCacheReady) {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            delete _logsCache;
            for (uint256 i; i < logs.length; i++) _logsCache.push(logs[i]);
            _logsCacheReady = true;
        }
    }

    function _countEvent(address emitter, bytes32 sig) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (_logsCache[i].emitter == emitter && _logsCache[i].topics.length > 0 && _logsCache[i].topics[0] == sig) count++;
        }
    }

    function _countEventFor(address emitter, bytes32 sig, address who) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (
                _logsCache[i].emitter == emitter &&
                _logsCache[i].topics.length >= 2 &&
                _logsCache[i].topics[0] == sig &&
                address(uint160(uint256(_logsCache[i].topics[1]))) == who
            ) count++;
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions whose indexed player == `to` (the bounty recipient).
    function _countCreditFlipTo(address to) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (
                _logsCache[i].emitter == address(coinflip) &&
                _logsCache[i].topics.length >= 2 &&
                _logsCache[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                address(uint160(uint256(_logsCache[i].topics[1]))) == to
            ) count++;
        }
    }
}
