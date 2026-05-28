// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGame} from "../../contracts/AfKing.sol";

/// @title AfKingSubscription -- Proves the v50.0 AFSUB-01..05 acceptance properties for the
///        AF_KING keeper: the pass-eviction-OR-refresh crossing gate (AFSUB-02/03), the
///        absence of any BURNIE-prepay window (AFSUB-01), and the gas-pegged single-creditFlip
///        autoBuy bounty (REW-02).
///
/// @notice Specifically:
///   - Pass-eviction-OR-refresh (AFSUB-02/03): at the `currentLevel > validThroughLevel` crossing
///     the keeper re-reads `IGame.lazyPassHorizon(player)` EXACTLY ONCE; a subscriber whose horizon
///     still covers `currentLevel` REFRESHES (SubscriptionExtendedFree, validThroughLevel = h, NO
///     BURNIE burn anywhere); a subscriber whose horizon no longer covers `currentLevel` is EVICTED
///     via the tombstone-then-reclaim path (dailyQuantity = 0, _removeFromSet, SubscriptionExpired(.,1))
///     WITHOUT reverting the autoBuy.
///   - No BURNIE in subscribe / no all-or-nothing renewal charge (AFSUB-01): subscribe no longer
///     issues any BURNIE keeper-burn; a no-pass subscriber's BURNIE balance is UNTOUCHED across
///     subscribe (so the v49 "shortfall" failure mode is structurally gone — there is no charge
///     to fail). The crossing-evict is the new "no-pass loses the sub" mechanism.
///   - Bounty (REW-02 / D-07): unchanged from v49 — the REWARDED keeper entrypoint is the
///     parameterless doWork() router; a doWork() whose autoBuy leg processes >= 1 buying
///     subscriber emits exactly ONE creditFlip to the caller (msg.sender), never per-item.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING, with the two
///      SUB-09 self-subscribes — VAULT + SDGNRS — already present). Test subscribers are driven
///      through the public subscribe() API. The crossing branch is reached by forcing a sub's
///      packed validThroughLevel to a value strictly below the current game level via a single
///      targeted slot write on the _subOf mapping (deterministic, avoids relying on real
///      gameplay advancing the level). Test-only: no contracts/*.sol mutated.
///
/// @dev v50.0 D-IMPL-02 (test-fixture full alignment): this file migrates from the v49 pass-OR-pay
///      day-31 renewal shape to the v50 pass-eviction-OR-refresh shape at the level crossing.
///      The migration is BEHAVIOR-PRESERVING in spirit: a pass-holder still avoids being
///      terminated at the "transition" (refresh ≡ free-extend); a non-pass-holder is still
///      terminated (evict ≡ shortfall failure). Only the MECHANISM changes: level vs. day;
///      tombstone-via-dailyQuantity vs. all-or-nothing-burn-shortfall.
contract AfKingSubscription is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing storage slots (4-slot pinned layout, per AfKing.sol)
    // -------------------------------------------------------------------------
    /// @dev _subOf mapping root slot (address => Sub packed in one slot).
    uint256 private constant SUBOF_SLOT = 1;

    // Sub packed-field byte offsets re-derived from the post-AFSUB layout: slot offset 5 is
    // repurposed in-place to `uint32 validThroughLevel` (same offset and width as the v49 slot —
    // D-11 / Plan 335-04 Task 1). The two standalone bools were already collapsed into `flags`
    // (v47 OPENE-01) and a 20-byte `fundingSource` appended at offset 11.
    uint256 private constant OFF_DAILY = 0;              // uint8 dailyQuantity      (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;          // uint32 lastAutoBoughtDay (bytes 1..4)
    uint256 private constant OFF_VALIDTHROUGHLEVEL = 5;  // uint32 validThroughLevel (bytes 5..8) — v50.0 AFSUB-01 in-place repurpose
    uint256 private constant OFF_REINVEST = 9;           // uint8 reinvestPct        (byte 9)
    uint256 private constant OFF_FLAGS = 10;             // uint8 flags (bit 0 freed; bits 1+2 = drainFirst/useTickets)
    uint256 private constant OFF_FUNDING_SOURCE = 11;    // address fundingSource    (bytes 11..30)

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — one per creditFlip.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    /// @dev AfKing event signatures used to assert the crossing branch taken.
    bytes32 private constant EXTENDED_FREE_SIG = keccak256("SubscriptionExtendedFree(address,uint32)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 3a — Pass-eviction-OR-refresh crossing gate (AFSUB-02 / AFSUB-03)
    // =========================================================================

    /// @notice AFSUB-03 (REFRESH branch): at the crossing (`currentLevel > sub.validThroughLevel`)
    ///         a subscriber whose `lazyPassHorizon(player)` STILL COVERS `currentLevel` is REFRESHED
    ///         in place — SubscriptionExtendedFree emitted, `validThroughLevel` stamped to `h`,
    ///         dailyQuantity preserved, NO eviction, NO BURNIE burn. Deity = sentinel horizon
    ///         (`type(uint24).max`), which always covers the current level.
    function testCrossingPassHolderRefreshedNotEvicted() public {
        address pass = makeAddr("pass_holder");
        _grantDeityPass(pass); // lazyPassHorizon(pass) = type(uint24).max (deity sentinel)
        _subscribeTicketMode(pass, 1); // no BURNIE charge at subscribe under AFSUB-01
        _approveKeeper(pass);
        _fundPool(pass, 1 ether); // pool funding so the post-refresh purchase can succeed
        _forceCrossingDue(pass); // validThroughLevel = 0 -> currentLevel > 0 -> crossing fires

        uint256 burnieBefore = coin.balanceOf(pass);

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_pass"));
        afKing.autoBuy(50);

        // REFRESH taken: SubscriptionExtendedFree emitted; NO SubscriptionExpired (evict) for this sub.
        assertEq(_countEvent(address(afKing), EXTENDED_FREE_SIG), 1, "pass-holder refreshed at crossing");
        assertEq(_countEventFor(address(afKing), SUB_EXPIRED_SIG, pass), 0, "pass-holder NOT evicted");

        // NO BURNIE involvement: AFSUB-01 removed the BURNIE-prepay window entirely.
        assertEq(coin.balanceOf(pass), burnieBefore, "no BURNIE burned at crossing (AFSUB-01)");

        // Refresh stamped a horizon strictly past the current level (deity = uint24.max).
        assertGt(
            afKing.subscriptionOf(pass).validThroughLevel,
            uint32(_currentLevel()),
            "validThroughLevel refreshed past current level"
        );
        // Sub still active (dailyQuantity preserved, still in iterable set).
        assertGt(afKing.subscriptionOf(pass).dailyQuantity, 0, "refreshed sub stays active");
        assertGt(_subscriberIndexOf(pass), 0, "refreshed sub stays in the iterable set");
    }

    /// @notice AFSUB-03 (EVICT branch): at the crossing a subscriber whose `lazyPassHorizon(player)`
    ///         NO LONGER COVERS `currentLevel` (no pass → horizon == 0 < currentLevel) is EVICTED via
    ///         the tombstone-then-reclaim path. dailyQuantity zeroed, _removeFromSet fired,
    ///         SubscriptionExpired(player, 1) emitted, autoBuy does NOT revert. The v49 swap-pop
    ///         invariant (membership ⟺ packed != 0) is preserved (Pitfall P6 — eviction routes
    ///         through the existing tombstone-shape, not a direct mid-sweep removal).
    function testCrossingNoPassEvictedViaTombstone() public {
        address nopass = makeAddr("no_pass");
        // No grantDeityPass: lazyPassHorizon(nopass) == 0 (no deity bit, no frozenUntilLevel).
        _subscribeTicketMode(nopass, 1); // AFSUB-01: no BURNIE charge regardless of pass state
        _approveKeeper(nopass);
        _fundPool(nopass, 1 ether);
        _forceCrossingDue(nopass);

        uint256 burnieBefore = coin.balanceOf(nopass);

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_nopass"));
        afKing.autoBuy(50); // MUST NOT revert despite the eviction

        // EVICTION taken via tombstone — assert the exact reclaim shape (SUB-07 invariant + swap-pop).
        assertGe(_countEvent(address(afKing), SUB_EXPIRED_SIG), 1, "no-pass evicted at crossing");
        assertEq(_countEventFor(address(afKing), EXTENDED_FREE_SIG, nopass), 0, "no-pass did NOT refresh");
        assertEq(afKing.subscriptionOf(nopass).dailyQuantity, 0, "tombstoned (dailyQuantity zeroed)");
        assertEq(_subscriberIndexOf(nopass), 0, "removed from iterable set (swap-pop)");

        // AFSUB-01: no BURNIE involvement on the eviction path either.
        assertEq(coin.balanceOf(nopass), burnieBefore, "no BURNIE burned on eviction (AFSUB-01)");
    }

    // =========================================================================
    // Task 3b — AFSUB-01: no BURNIE prepay window at subscribe; horizon-encoded only
    // =========================================================================

    /// @notice AFSUB-01: subscribe NEVER charges BURNIE — neither the v49 SUB-01 window-1 burn nor
    ///         the v49 day-31 renewal extract exists. A no-pass subscriber's BURNIE balance is
    ///         UNCHANGED across subscribe; their `validThroughLevel` is encoded as `lazyPassHorizon`
    ///         (zero for a no-pass subscriber).
    function testSubscribeNoBurnieChargeRegardlessOfPass() public {
        // (a) no-pass subscriber: zero BURNIE → subscribe MUST succeed; balance unchanged.
        address nopass = makeAddr("subscribe_nopass");
        uint256 nopassBefore = coin.balanceOf(nopass); // == 0
        vm.prank(nopass);
        afKing.subscribe(address(0), false, true, 1, 0, address(0)); // MUST NOT revert under AFSUB-01
        assertEq(coin.balanceOf(nopass), nopassBefore, "AFSUB-01: no BURNIE burned at subscribe (no-pass)");
        // horizon = 0 stamped into validThroughLevel (no pass → no coverage).
        assertEq(afKing.subscriptionOf(nopass).validThroughLevel, 0, "no-pass subscriber: validThroughLevel = 0");

        // (b) pass-holder: ditto — deity holder also has zero BURNIE charge.
        address pass = makeAddr("subscribe_pass");
        _grantDeityPass(pass);
        uint256 passBefore = coin.balanceOf(pass);
        vm.prank(pass);
        afKing.subscribe(address(0), false, true, 1, 0, address(0));
        assertEq(coin.balanceOf(pass), passBefore, "AFSUB-01: no BURNIE burned at subscribe (pass-holder)");
        // Deity sentinel = type(uint24).max stamped into validThroughLevel.
        assertEq(
            afKing.subscriptionOf(pass).validThroughLevel,
            uint32(type(uint24).max),
            "deity subscriber: validThroughLevel = sentinel (uint24.max)"
        );
    }

    /// @notice AFSUB-02: the per-iter validity check is a pure stored-field compare —
    ///         `currentLevel <= sub.validThroughLevel`. A sub whose horizon STILL COVERS the current
    ///         level is NOT at the crossing this autoBuy; no SubscriptionExtendedFree fires (refresh
    ///         is the crossing branch only), the sub buys normally, and the per-iter path consumes
    ///         ZERO external `lazyPassHorizon` reads. Asserts the non-crossing case: pass-holder
    ///         already at-or-above current level is processed cleanly with NO refresh event.
    function testNonCrossingPassHolderBuysWithoutRefresh() public {
        address pass = makeAddr("nx_pass_holder");
        _grantDeityPass(pass); // horizon = uint24.max
        _subscribeTicketMode(pass, 1); // validThroughLevel = uint24.max (deity sentinel)
        _approveKeeper(pass);
        _fundPool(pass, 1 ether);
        // DO NOT force crossing — leave validThroughLevel at the sentinel so currentLevel <= horizon.

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_nx"));
        afKing.autoBuy(50);

        // Non-crossing path: NO refresh event, NO eviction event for this sub.
        assertEq(_countEventFor(address(afKing), EXTENDED_FREE_SIG, pass), 0, "non-crossing: no refresh");
        assertEq(_countEventFor(address(afKing), SUB_EXPIRED_SIG, pass), 0, "non-crossing: no eviction");
        // Sub still active.
        assertGt(_subscriberIndexOf(pass), 0, "non-crossing sub stays in set");
    }

    /// @notice TST-02 D-TST02-02 (AFSUB-02 no-SLOAD oracle): hot-path-accurate empirical proof
    ///         that the non-crossing AfKing autoBuy iteration performs ZERO external
    ///         `IGame.lazyPassHorizon` reads. Under the v50.0 AFSUB-02 stored-field gate, an
    ///         iteration where `currentLevel <= sub.validThroughLevel` MUST be a cheap stored-field
    ///         compare with no external pass read — only the crossing branch (AfKing.sol:627-647)
    ///         calls `GAME.lazyPassHorizon(player)` at line :628. Empirically re-attests the
    ///         GASOPT-05-class no-regression invariant carried from v49 (the per-iter
    ///         `isOperatorApproved` SLOAD was already removed; this oracle proves no equivalent
    ///         per-iter external pass read crept back in under AFSUB).
    /// @dev    This is the FIRST `vm.expectCall` usage in the entire `test/` tree per
    ///         RESEARCH §Summary finding 1. Pitfall 1 (RESEARCH §5) enforces strict staging
    ///         order: STAGE (deity grant, subscribe, approve, fund) → `vm.expectCall(..., 0)` →
    ///         `vm.prank` → `afKing.autoBuy(50)`. NOTHING between the cheatcode and the autoBuy
    ///         invocation; the cheatcode begins counting from the next external call, so any
    ///         interleaved staging call would consume the budget vacuously.
    /// @dev    Cheatcode auto-verifies on test teardown — no explicit assertEq needed. If any
    ///         `IGame.lazyPassHorizon` call fires after the `vm.expectCall` line (i.e. during
    ///         the autoBuy sweep), the test fails at teardown with
    ///         `vm.expectCall: counted N of expected 0 calls`.
    function testNonCrossingPathPerformsZeroLazyPassHorizonSloads() public {
        // STEP 1 — STAGE FIRST. All external calls happen here, BEFORE the cheatcode is invoked.
        // Deity sentinel pins validThroughLevel = uint24.max (set at subscribe via the
        // `lazyPassHorizon` snapshot at AfKing.sol:419), guaranteeing the non-crossing branch
        // (`currentLevel <= sub.validThroughLevel`) for the entire game lifetime.
        address pass = makeAddr("nx_no_sload_holder");
        _grantDeityPass(pass);          // lazyPassHorizon(pass) = type(uint24).max
        _subscribeTicketMode(pass, 1);  // validThroughLevel = uint24.max stamped at subscribe
        _approveKeeper(pass);
        _fundPool(pass, 1 ether);

        // STEP 2 — Stage the cheatcode. Selector-only encoding matches ANY (address) arg, so
        // an external call into `lazyPassHorizon(player)` for any `player` would be counted.
        // The third arg `0` asserts EXACTLY ZERO calls into that selector at `address(game)` for
        // the remainder of the test.
        vm.expectCall(
            address(game),
            abi.encodeWithSelector(IGame.lazyPassHorizon.selector),
            0
        );

        // STEP 3 — Prank the keeper caller.
        vm.prank(makeAddr("autoBuyer_no_sload_check"));

        // STEP 4 — Drive the non-crossing autoBuy sweep. NO statements between STEP 2 and here.
        afKing.autoBuy(50);

        // STEP 5 — End of test (cheatcode auto-verifies at teardown). No explicit assertEq.
    }

    // =========================================================================
    // Task 3c — Gas-pegged single-creditFlip autoBuy bounty (REW-02)
    // =========================================================================

    /// @notice REW-02 (D-07 re-homed to doWork): the REWARDED keeper entrypoint is the parameterless
    ///         `doWork()` router (the standalone `autoBuy(count)` is UNREWARDED, 330-07). A doWork()
    ///         call whose autoBuy leg processes >= 1 buying subscriber emits EXACTLY ONE creditFlip
    ///         to the caller (never per-item) — the REW-02 one-bounty-per-tx property.
    function testDoWorkEmitsExactlyOneBuyBounty() public {
        address s1 = makeAddr("buy_s1");
        address s2 = makeAddr("buy_s2");
        _setupHealthyBuyingSub(s1);
        _setupHealthyBuyingSub(s2);

        address keeper = makeAddr("bounty_keeper");

        vm.recordLogs();
        vm.prank(keeper);
        afKing.doWork(); // the rewarded router; autoBuy is the highest-priority leg (RD-1)

        // EXACTLY ONE creditFlip emission for the whole tx (the single unified bounty), to the caller.
        assertEq(_countCreditFlipTo(keeper), 1, "exactly one bounty creditFlip per doWork tx (REW-02)");
    }

    /// @notice REW-02 tail: a standalone `autoBuy` that processes ZERO buying subscribers is a
    ///         NO-OP (a no-buy chunk returns 0 so the doWork router can make progress). Every active
    ///         sub is forced AlreadyAutoBoughtToday so the loop produces no buys; assert the call
    ///         succeeds and stamps no fresh buy.
    function testZeroBuyAutoBuyIsNoOp() public {
        // Mark the two SUB-09 deploy subs (VAULT, SDGNRS) already-autoBought-today so they are skipped.
        // NOTE: under v50.0 AFSUB-01, the SUB-09 deploy-time entries subscribe with validThroughLevel =
        // lazyPassHorizon(VAULT/SDGNRS) — VAULT carries the permanent deity bit (DegenerusGame ctor)
        // so VAULT's horizon = uint24.max (no first-crossing eviction); SDGNRS holds no pass so its
        // horizon = 0 and it would evict on the first crossing iteration. Here we BYPASS the
        // crossing/refresh/evict path entirely by stamping lastAutoBoughtDay so the per-iter
        // AlreadyAutoBoughtToday skip fires first (AfKing._autoBuy:613).
        _markAutoBoughtToday(ContractAddresses.VAULT);
        _markAutoBoughtToday(ContractAddresses.SDGNRS);
        uint32 vaultStampBefore = _lastAutoBoughtDayOf(ContractAddresses.VAULT);

        vm.prank(makeAddr("empty_autoBuyer"));
        afKing.autoBuy(50); // MUST NOT revert
        assertEq(
            _lastAutoBoughtDayOf(ContractAddresses.VAULT),
            vaultStampBefore,
            "no-buy chunk is a no-op: no fresh buy stamped (no double-buy)"
        );
    }

    /// @notice autoBuy(0) uses the default batch (BUY_BATCH) — 0 = default; it does NOT
    ///         revert, running a default-size unrewarded manual clear.
    function testAutoBuyZeroMaxCountUsesDefaultBatch() public {
        vm.prank(makeAddr("zero_autoBuyer"));
        afKing.autoBuy(0); // no revert — processes the default batch
    }

    // =========================================================================
    // Task 3d — OPEN-E cross-account subscribe-only auth (OPENE-04)
    // =========================================================================

    /// @notice OPENE-04 unapproved-source-refused: subscribing with an UNAPPROVED non-zero non-self
    ///         fundingSource reverts NotApproved at subscribe (the cross-account gate is checked HERE);
    ///         after the source approves the subscriber, the SAME subscribe is honored. Proves the
    ///         money-holder-grants-spender direction: S must approve M for M to draw from S.
    /// @dev    Under AFSUB-01 there is no BURNIE charge at subscribe — the ONLY thing the
    ///         fundingSource gates now is the future per-day ETH draw routing (OPENE-02 ETH
    ///         direction). The OPENE-04 consent gate itself is UNCHANGED.
    function testUnapprovedFundingSourceRefusedThenHonored() public {
        address s = makeAddr("auth_s");
        address m = makeAddr("auth_m");
        // No BURNIE pre-funding needed under AFSUB-01 (subscribe is BURNIE-free).

        // REFUSED: M has NOT been approved by S -> the non-zero non-self source reverts NotApproved.
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        afKing.subscribe(address(0), false, true, 1, 0, s);

        // S approves M on the game; now the SAME subscribe is honored (source stored).
        vm.prank(s);
        game.setOperatorApproval(m, true);
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, s);

        assertEq(afKing.subscriptionOf(m).fundingSource, s, "approved source honored (stored as S)");
    }

    /// @notice OPENE-04 revoke-does-NOT-stop-an-active-sub (subscribe-only auth): after S approves M
    ///         and M subscribes with fundingSource = S, S REVOKES (setOperatorApproval(M,false)). The
    ///         autoBuy STILL draws ETH from S's pool — the keeper trusts the stored source and never
    ///         re-checks approval at the per-day draw. The sub is stopped only when S DEFUNDS (the
    ///         pool runs dry -> InsufficientPool funding-skip kills the NORMAL sub) or M cancels.
    /// @dev    Under AFSUB-01 the v49 day-31 BURNIE auto-extract path is gone; the trust-the-
    ///         sub temporal-bound property survives by being asserted on the per-day ETH draw.
    function testRevokeDoesNotStopActiveSubButDefundDoes() public {
        address s = makeAddr("revoke_s");
        address m = makeAddr("revoke_m");
        // S approves M on the game (the OPENE-04 cross-account gate honored at subscribe).
        vm.prank(s);
        game.setOperatorApproval(m, true);
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, s); // source = S, no BURNIE charge (AFSUB-01)
        _approveKeeper(m);
        _fundPool(s, 1 ether); // S funds the per-day ETH draw

        uint256 sPoolBefore = afKing.poolOf(s);

        // S REVOKES M's approval AFTER the sub is active.
        vm.prank(s);
        game.setOperatorApproval(m, false);
        assertFalse(game.isOperatorApproved(s, m), "S has revoked M");

        vm.recordLogs();
        vm.prank(makeAddr("revoke_autoBuyer_1"));
        afKing.autoBuy(50);

        // SUBSCRIBE-ONLY AUTH: the per-day draw STILL debited S's pool despite the revoke (no re-check).
        assertLt(afKing.poolOf(s), sPoolBefore, "per-day draw still debited S after revoke (trust-the-sub)");
        assertEq(_countEventFor(address(afKing), SUB_EXPIRED_SIG, m), 0, "active sub NOT terminated by a revoke");
        assertGt(_subscriberIndexOf(m), 0, "M's sub stays in the set after S revokes");

        // Now S DEFUNDS (the pool runs dry). Advance one keeper-local day so the cursor resets, then
        // run autoBuy — M's draw funding-skips and the NORMAL sub auto-pauses via InsufficientPool.
        // First drain S's remaining pool to zero so the next draw cannot fund.
        // Plan 335-06 fix: read poolOf(s) BEFORE vm.prank, since vm.prank only affects the very next
        // external call — calling afKing.poolOf inline as the prank's "next call" consumed the prank
        // stamp before withdraw ran, so withdraw ended up with the test contract as msg.sender and
        // reverted InsufficientBalance against a zero pool.
        uint256 sPoolRemaining = afKing.poolOf(s);
        vm.prank(s);
        afKing.withdraw(sPoolRemaining);
        vm.warp(block.timestamp + 1 days);
        // Re-fund M's claimable to 0 (sentinel only) so the draw must come from the (now-zero) S pool.

        // A healthy buyer so the defund autoBuy still produces a buy.
        address healthy = makeAddr("revoke_healthy");
        _setupHealthyBuyingSub(healthy);

        // Plan 335-06 fix: the test issues a second `vm.recordLogs()` after the first; reset the
        // drain-once cache so the second autoBuy's logs are captured (otherwise the first drain
        // already set `_logsCacheReady = true` and subsequent counts read stale buffer).
        _resetLogsCache();
        vm.recordLogs();
        vm.prank(makeAddr("revoke_autoBuyer_2"));
        afKing.autoBuy(50);

        // Defund -> InsufficientPool funding-skip auto-pauses M (NORMAL-sub kill, NOT the exempt
        // VAULT/SDGNRS — those have pinned-identity exemption tested separately).
        assertGe(_countEventFor(address(afKing), SUB_EXPIRED_SIG, m), 1, "defunded source -> auto-pause kill");
        assertEq(afKing.subscriptionOf(m).dailyQuantity, 0, "M's sub auto-paused once S defunds");
        assertEq(_subscriberIndexOf(m), 0, "M removed from the set on the defund auto-pause");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Current game level (game.level() auto-getter for the `uint24 public level` storage var).
    function _currentLevel() internal view returns (uint24) {
        return game.level();
    }

    /// @dev Subscribe `who` in ticket mode, dailyQuantity q. Under v50.0 AFSUB-01 there is no BURNIE
    ///      charge at subscribe regardless of pass state.
    function _subscribeTicketMode(address who, uint8 q) internal {
        vm.prank(who);
        afKing.subscribe(address(0), false, true, q, 0, address(0)); // self-consent, ticket mode, no reinvest, self-funded
    }

    /// @dev A fully-healthy buying sub: ticket mode, operator-approved, funded pool. Under AFSUB-01
    ///      no BURNIE pre-fund is needed. The sub is NOT at the crossing (validThroughLevel encoded
    ///      from lazyPassHorizon at subscribe; for a no-pass subscriber this is 0, so a non-zero
    ///      currentLevel would trigger the crossing — this helper is used only at currentLevel == 0).
    function _setupHealthyBuyingSub(address who) internal {
        _subscribeTicketMode(who, 1);
        _approveKeeper(who);
        _fundPool(who, 1 ether);
    }

    /// @dev Approve AfKing as `who`'s game operator (the autoBuy's SUB-02 isOperatorApproved gate).
    function _approveKeeper(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
    }

    /// @dev Credit `who`'s AfKing pool with `amount` ETH (via depositFor).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    /// @dev Grant `who` the permanent deity bit so lazyPassHorizon(who) == type(uint24).max. Mirrors
    ///      the game constructor's VAULT/SDGNRS deity seeding: set bit HAS_DEITY_PASS_SHIFT (184) in
    ///      mintPacked_[who] (slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Force `who`'s sub into the crossing branch: write validThroughLevel = 0 (so any
    ///      currentLevel > 0 triggers `currentLevel > sub.validThroughLevel`). Clear lastAutoBoughtDay
    ///      so the AlreadyAutoBoughtToday skip does not fire first. Also bump `currentLevel` from 0 to
    ///      1 via a direct slot write so the crossing predicate is reachable even on a fresh fixture
    ///      where game.level() returns 0.
    /// @dev `level` lives in DegenerusGameStorage SLOT 0 packed as:
    ///        bytes 0..3   uint32 purchaseStartDay
    ///        bytes 4..7   uint32 dailyIdx
    ///        bytes 8..13  uint48 rngRequestTime
    ///        bytes 14..16 uint24 level                  ← target field
    ///        byte 17      bool jackpotPhaseFlag
    ///      The Phase 335-06 helper-fix replaces the v49-era assumption that `level` sat at the low
    ///      24 bits (it never did under the current Storage layout) — the byte-14 shift below
    ///      writes to the correct field.
    uint256 private constant LEVEL_BYTE_OFFSET = 14;
    function _forceCrossingDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        // Clear lastAutoBoughtDay (bytes 1..4) and validThroughLevel (bytes 5..8).
        uint256 mask = (uint256(0xFFFFFFFF) << (OFF_LASTSWEPT * 8)) | (uint256(0xFFFFFFFF) << (OFF_VALIDTHROUGHLEVEL * 8));
        packed &= ~mask;
        // validThroughLevel = 0, lastAutoBoughtDay = 0.
        vm.store(address(afKing), slot, bytes32(packed));
        // Ensure the game's level is strictly greater than the sub's validThroughLevel (= 0). The
        // `level` storage var is `uint24` packed at bytes 14..16 of DegenerusGameStorage slot 0
        // (see Storage layout comment above). Bump those 24 bits to 1 if currently 0 so
        // `currentLevel > validThroughLevel` is true.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (LEVEL_BYTE_OFFSET * 8);
        if (uint24((slot0 & levelMask) >> (LEVEL_BYTE_OFFSET * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (LEVEL_BYTE_OFFSET * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot) — the GASOPT-04 buy oracle.
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    /// @dev Force `who`'s lastAutoBoughtDay = today so the AlreadyAutoBoughtToday skip (reason 2) fires.
    function _markAutoBoughtToday(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        packed &= ~(uint256(0xFFFFFFFF) << (OFF_LASTSWEPT * 8));
        packed |= (uint256(_today()) << (OFF_LASTSWEPT * 8));
        vm.store(address(afKing), slot, bytes32(packed));
    }

    /// @dev Read AfKing's 1-indexed subscriber index for `who` (slot 3) — 0 means not in the set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(3)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Cached drained logs, populated once per test via `_drainLogs()` after `vm.recordLogs()`.
    ///      `vm.getRecordedLogs()` is CONSUMING (empties the buffer); to allow multiple per-test
    ///      assertions across different (sig, who) combinations the v50.0 migration switches to a
    ///      drain-once cache. Each test calls `vm.recordLogs()` -> drives the autoBuy -> calls
    ///      `_drainLogs()` once -> then reads `_countEvent` / `_countEventFor` / `_countCreditFlipTo`
    ///      against the cache. Auto-drained lazily on first count call.
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

    /// @dev Reset the drain-once cache so a subsequent `vm.recordLogs()` round is captured fresh.
    ///      Plan 335-06 fix: needed by tests that issue multiple `vm.recordLogs()` calls per test
    ///      (e.g. testRevokeDoesNotStopActiveSubButDefundDoes runs autoBuy twice with two record
    ///      windows). Without this reset, the first drain locks the cache for the rest of the test.
    function _resetLogsCache() internal {
        delete _logsCache;
        _logsCacheReady = false;
    }

    /// @dev Count events with `sig` emitted by `emitter` in the recorded logs. Drains the buffer
    ///      lazily on first call per test; subsequent calls re-use the cached snapshot so multiple
    ///      assertions per autoBuy work correctly (the v49 helper consumed the buffer per call,
    ///      which silently zeroed every assertion after the first).
    function _countEvent(address emitter, bytes32 sig) internal returns (uint256 count) {
        _drain();
        for (uint256 i; i < _logsCache.length; i++) {
            if (_logsCache[i].emitter == emitter && _logsCache[i].topics.length > 0 && _logsCache[i].topics[0] == sig) count++;
        }
    }

    /// @dev Count events with `sig` emitted by `emitter` whose indexed first arg == `who` in the
    ///      recorded logs. Used to discriminate per-player event counts (e.g. one sub's eviction
    ///      vs. another sub's refresh in the same autoBuy).
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
