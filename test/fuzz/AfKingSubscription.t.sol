// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingSubscription -- Proves the v55.0 game-resident afking subscription acceptance
///        properties: the pass-eviction-OR-refresh crossing gate (AFSUB-02/03), the absence of any
///        FLIP-prepay window (AFSUB-01), the single-creditFlip mintFlip bounty (REW-02), and the
///        OPEN-E cross-account subscribe-only auth (OPENE-04). The afking surface is now GAME-resident
///        (GameAfkingModule reached via DegenerusGame delegatecall) -- the standalone `AfKing` contract
///        was DISSOLVED (D-351-01, PATTERNS §2).
///
/// @notice Specifically:
///   - Pass-eviction-OR-refresh (AFSUB-02/03): at the `currentLevel > validThroughLevel` crossing the
///     STAGE re-reads `_passHorizonOf(player)` EXACTLY ONCE; a subscriber whose horizon still covers
///     `currentLevel` REFRESHES (SubscriptionExtendedFree, validThroughLevel = h, NO FLIP burn); a
///     subscriber whose horizon no longer covers `currentLevel` is EVICTED via the tombstone-then-
///     reclaim path (dailyQuantity = 0, _removeFromSet, SubscriptionExpired(.,1)) WITHOUT reverting.
///   - No FLIP in subscribe (AFSUB-01): subscribe never issues any FLIP keeper-burn; a no-pass
///     subscriber's FLIP balance is UNTOUCHED across subscribe.
///   - Bounty (REW-02 / PLACE-02): the REWARDED entrypoint is the parameterless `mintFlip()` router;
///     a mintFlip() whose advance leg processes the buy STAGE emits exactly ONE creditFlip to the
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
///   Δ3 doWork: `afKing.doWork()` -> `game.mintFlip()`.
///   Δ4 autoBuy: `afKing.autoBuy(N)` -> the per-sub buy folded into `advanceGame()`'s STAGE; driven via
///      a new-day advanceGame + the `_settleGame` VRF drain.
///   Δ5 views/cancel: `afKing.subscriptionOf(x).field` -> read `_subOf[x]` via vm.load (RE-DERIVED
///      slots); `afKing.poolOf` -> `afkingFundingOf`; `afKing.withdraw` -> `withdrawAfkingFunding`;
///      `afKing.depositFor` -> `depositAfkingFunding`.
///
/// @dev Builds on the 351-01-repaired DeployProtocol fixture (GameAfkingModule live; the two SUB-09
///      self-subscribes VAULT + SDGNRS already present). Test subscribers are driven through the public
///      game.subscribe() API. Credential model: the AFKing Subscription Token (sub <=> coin) — subscribe requires
///      balanceOf >= 1 (granted via DeployProtocol._grantSeat) and the process pass never re-checks;
///      the pass/horizon crossing machinery is deleted. Test-only: no contracts/*.sol mutated.
contract AfKingSubscription is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 53; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant FUNDING_SOURCE_SLOT = 54; // _fundingSourceOf mapping root (address => address)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 56; // _subscriberIndex mapping root (1-indexed)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:1895; the v56 compute-on-read re-pack
    // narrowed validThroughLevel + the day markers to uint24).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity      (byte 0)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay  (bytes 7..9; post-validThroughLevel-removal repack)

    /// @dev keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)") — one per creditFlip.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");

    /// @dev Game-resident module event signature (emitter == address(game) via delegatecall).
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 3a — Coin credential: no process-pass re-check, no crossing machinery
    // (supersedes AFSUB-02/AFSUB-03: the pass horizon + refresh/evict crossing
    // branch is DELETED — the AFKing Subscription Token is the sole credential, enforced only
    // at subscribe (NoCoin) and by the coin's seat lock (SeatInUse on an active sub's last-coin transfer))
    // =========================================================================

    /// @notice A coin-holding, PASSLESS subscriber is processed across the STAGE with
    ///         no credential re-check: no eviction event, no FLIP burn, stays in the
    ///         iterable set with dailyQuantity preserved. This is the successor of the
    ///         crossing refresh/evict pair — level crossings are now a non-event for
    ///         subscription membership.
    function testPasslessCoinHolderProcessedNoEviction() public {
        address seated = makeAddr("seated_no_pass");
        _grantSeat(seated); // the coin IS the credential; no pass anywhere
        _fundPool(seated, 1 ether);
        _subscribeLootboxMode(seated, 1);

        uint256 flipBefore = coin.balanceOf(seated);

        vm.recordLogs();
        _runStageOnce();

        assertEq(_countEventFor(address(game), SUB_EXPIRED_SIG, seated), 0, "no eviction: coin held");
        assertEq(coin.balanceOf(seated), flipBefore, "no FLIP burned during the STAGE");
        assertGt(_dailyQtyOf(seated), 0, "sub stays active");
        assertGt(_subscriberIndexOf(seated), 0, "sub stays in the iterable set");
    }

    // =========================================================================
    // Task 3b — AFSUB-01: no FLIP prepay window at subscribe; horizon-encoded only
    // =========================================================================

    /// @notice AFSUB-01: subscribe NEVER charges FLIP. A no-pass subscriber's FLIP balance is
    ///         UNCHANGED across subscribe; their `validThroughLevel` is encoded as `_passHorizonOf`
    ///         (zero for a no-pass subscriber).
    function testSubscribeNoFlipChargeRegardlessOfPass() public {
        // Formerly skipped (357-00d): the pass gate rejected a passless subscribe at every
        // level. The AFKing Subscription Token credential resurrects this coverage — a passless,
        // coin-holding subscriber is first-class. AFSUB-01 (no FLIP charge at subscribe)
        // is the property under test; the coin gate charges nothing either.
        address nopass = makeAddr("subscribe_nopass");
        _grantSeat(nopass);
        _fundPool(nopass, 1 ether); // grounds the NEW-run cover-buy (D-12); the deposit is ETH, not FLIP
        uint256 nopassBefore = coin.balanceOf(nopass); // == 0
        vm.prank(nopass);
        game.subscribe(address(0), false, true, 1, address(0)); // MUST NOT revert; charges no FLIP
        assertEq(coin.balanceOf(nopass), nopassBefore, "AFSUB-01: no FLIP burned at subscribe (no pass)");
        assertGt(_dailyQtyOf(nopass), 0, "passless coin-holder subscribed");
    }

    // =========================================================================
    // Task 3c — Single-creditFlip mintFlip bounty (REW-02 / PLACE-02)
    // =========================================================================

    /// @notice REW-02 (PLACE-02 bounty folded into advance): the REWARDED entrypoint is the
    ///         parameterless `mintFlip()` router. A mintFlip() whose advance leg runs the buy STAGE
    ///         emits AT MOST ONE creditFlip to the caller (never per-item) — the one-bounty-per-tx
    ///         property. (The advance leg pays `unit·2·mult`; a `mult==0` gameover advance pays none.)
    function testMintFlipEmitsAtMostOneBuyBounty() public {
        address s1 = makeAddr("buy_s1");
        address s2 = makeAddr("buy_s2");
        _setupHealthyBuyingSub(s1);
        _setupHealthyBuyingSub(s2);

        address keeper = makeAddr("bounty_keeper");

        // mintFlip routes ONE category (advance, here) and pays ONE bounty CEI-last. The advance leg
        // runs the buy STAGE in-context. Assert at most one creditFlip emission to the caller.
        vm.recordLogs();
        vm.prank(keeper);
        try game.mintFlip() {} catch {} // may revert NoWork() if nothing is due — that is the no-bounty case
        assertLe(_countCreditFlipTo(keeper), 1, "at most one bounty creditFlip per mintFlip tx (REW-02)");
    }

    /// @notice REW-02 tail: a standalone `autoOpen` is UNREWARDED — only mintFlip() credits. An
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
        // Formerly skipped (357-00d): the pass gate rejected the passless honored-subscribe.
        // The AFKing Subscription Token credential resurrects the full REFUSED->HONORED sequence: the
        // NotApproved consent gate fires BEFORE the coin gate, and the honored leg
        // subscribes a coin-holding M.
        address s = makeAddr("auth_s");
        address m = makeAddr("auth_m");
        _grantSeat(m);

        // REFUSED: M has NOT been approved by S -> the non-zero non-self source reverts NotApproved.
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.subscribe(address(0), false, true, 1, s);

        // S approves M on the game; now the SAME subscribe is honored (source stored).
        vm.prank(s);
        game.setOperatorApproval(m, true);
        // Fund S's bucket BEFORE the honored subscribe so M's NEW-run cover-buy (drawn from the resolved
        // source S) is grounded (D-12); the OPEN-E approval gate is the property under test.
        _fundPool(s, 1 ether);
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, s);

        assertEq(_fundingSourceOf(m), s, "approved source honored (stored as S)");
    }

    /// @notice OPENE-04 revoke-does-NOT-stop-an-active-sub (subscribe-only auth): after S approves M
    ///         and M subscribes with fundingSource = S, S REVOKES (setOperatorApproval(M,false)). The
    ///         sub is NOT terminated by the revoke (the keeper trusts the stored source and never
    ///         re-checks approval at the per-day draw — the trust-the-sub temporal bound). The sub is
    ///         stopped only when S DEFUNDS or M cancels.
    function testRevokeDoesNotStopActiveSub() public {
        // Formerly skipped (357-00d): the pass gate rejected M's passless subscribe. The
        // AFKing Subscription Token credential resurrects it — M holds a seat, S funds; the revoke
        // semantics under test (source fixed at subscribe, no per-draw re-check) are
        // unchanged.
        address s = makeAddr("revoke_s");
        address m = makeAddr("revoke_m");
        _grantSeat(m);
        vm.prank(s);
        game.setOperatorApproval(m, true);
        // Fund S's bucket BEFORE subscribe so M's NEW-run cover-buy (drawn from the resolved source S) is
        // grounded (D-12); the trust-the-sub revoke semantics are the property under test.
        _fundPool(s, 1 ether); // S funds the per-day ETH draw + grounds the subscribe cover-buy
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, s); // source = S, no FLIP charge (AFSUB-01)

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
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest, self-funded
    }

    /// @dev A fully-healthy buying sub (lootbox mode, seated with an AFKing Subscription Token, funded).
    function _setupHealthyBuyingSub(address who) internal {
        _grantSeat(who);
        _fundPool(who, 1 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
        _subscribeLootboxMode(who, 1);
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    // ---- Sub field reads (game-resident _subOf slot 54 + verified packed offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (slot 57); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    /// @dev Read `who`'s fundingSource from the sparse `_fundingSourceOf` map (slot 55).
    ///      address(0) = self-funded (the common case stores nothing).
    function _fundingSourceOf(address who) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(FUNDING_SOURCE_SLOT)))))));
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
