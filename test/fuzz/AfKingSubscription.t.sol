// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingSubscription -- Proves the testable acceptance of subscription correctness for the
///        AF_KING keeper: the pass-OR-pay renewal gate (SUB-01), the all-or-nothing burnForKeeper
///        charge (PROTO-02 / SUB-08), and the gas-pegged single-creditFlip autoBuy bounty (REW-02).
///
/// @notice Specifically:
///   - Pass-OR-pay (SUB-01): at the day-31 renewal branch a subscriber WITH an active lazy pass
///     (hasAnyLazyPass true) takes the FREE 30-day extend with NO burnForKeeper charge
///     (SubscriptionExtendedFree, windowPaid cleared); a subscriber WITHOUT a pass is charged via
///     the all-or-nothing burnForKeeper (BurnieAutoExtracted, windowPaid set).
///   - burnForKeeper all-or-nothing (PROTO-02 / SUB-08): a player with spendable BURNIE >= cost is
///     charged exactly `cost` and renews (windowPaid set, paidThroughDay reset); a player with
///     spendable < cost has NOTHING burned, burnForKeeper returns 0, and the autoBuy AUTO-PAUSES that
///     sub (dailyQuantity 0, removed from set, SubscriptionExpired) WITHOUT reverting the autoBuy.
///   - Bounty (REW-02): a autoBuy that processes >= 1 buying subscriber emits exactly ONE creditFlip
///     to the autoBuyer (msg.sender), gas-pegged (BOUNTY_ETH_TARGET-derived, never per-item); a autoBuy
///     that processes zero buys reverts NoSubscribersAutoBought.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING, with the two
///      SUB-09 self-subscribes — VAULT + SDGNRS — already present). Test subscribers are driven
///      through the public subscribe() API; the day-31 renewal branch is reached by forcing the
///      sub's packed paidThroughDay <= today via a single targeted slot write on the _subOf mapping
///      (deterministic, avoids a 31-day warp that would shift the keeper-local day for every sub).
///      BURNIE is funded via the GAME-gated mintForGame path. Test-only: no contracts/*.sol mutated.
contract AfKingSubscription is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing storage slots (4-slot pinned layout, per AfKing.sol)
    // -------------------------------------------------------------------------
    /// @dev _subOf mapping root slot (address => Sub packed in one slot).
    uint256 private constant SUBOF_SLOT = 1;

    // Sub packed-field byte offsets within the single Sub slot, re-derived from the
    // post-OPEN-E repack (319.1-01 AFTER layout): the two standalone bools collapsed into
    // `flags` and a 20-byte `fundingSource` address was appended, shifting lastAutoBoughtDay
    // 3->1, paidThroughDay 7->5, flags 12->10.
    uint256 private constant OFF_DAILY = 0;          // uint8 dailyQuantity   (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;      // uint32 lastAutoBoughtDay    (bytes 1..4)
    uint256 private constant OFF_PAIDTHROUGH = 5;    // uint32 paidThroughDay  (bytes 5..8)
    uint256 private constant OFF_REINVEST = 9;       // uint8 reinvestPct      (byte 9)
    uint256 private constant OFF_FLAGS = 10;         // uint8 flags (bit 0 = windowPaid)
    uint256 private constant OFF_FUNDING_SOURCE = 11; // address fundingSource (bytes 11..30)

    // -------------------------------------------------------------------------
    // BurnieCoin / mint constants
    // -------------------------------------------------------------------------
    /// @dev balanceOf mapping root slot in BurnieCoin (slot 1; slot 0 = _supply struct).
    uint256 private constant BURNIE_BALANCE_SLOT = 1;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — one per creditFlip.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    /// @dev AfKing event signatures used to assert the renewal branch taken.
    bytes32 private constant EXTENDED_FREE_SIG = keccak256("SubscriptionExtendedFree(address,uint32)");
    bytes32 private constant AUTO_EXTRACTED_SIG = keccak256("BurnieAutoExtracted(address,uint32,uint256)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 3a — Pass-OR-pay renewal gate (SUB-01)
    // =========================================================================

    /// @notice SUB-01: a PASS-HOLDING subscriber at the day-31 renewal branch takes the FREE extend
    ///         (SubscriptionExtendedFree, no burnForKeeper charge, no BURNIE burned) — the pass gate
    ///         short-circuits the charge entirely.
    function testRenewalPassHolderFreeExtendNoCharge() public {
        address pass = makeAddr("pass_holder");
        _grantDeityPass(pass); // hasAnyLazyPass(pass) == true
        _subscribeTicketMode(pass, 1, /*fundBurnie*/ false); // no BURNIE needed (pass = free at subscribe too)
        _approveKeeper(pass);
        _fundPool(pass, 1 ether); // pool funding so the post-renewal purchase can succeed
        _forceRenewalDue(pass); // paidThroughDay <= today -> renewal branch

        uint256 burnieBefore = coin.balanceOf(pass);

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_pass"));
        afKing.autoBuy(50);

        // FREE extend taken: SubscriptionExtendedFree emitted; NO BurnieAutoExtracted; balance intact.
        assertEq(_countEvent(address(afKing), EXTENDED_FREE_SIG), 1, "pass-holder free-extended");
        assertEq(_countEvent(address(afKing), AUTO_EXTRACTED_SIG), 0, "pass-holder NOT charged via burnForKeeper");
        assertEq(coin.balanceOf(pass), burnieBefore, "no BURNIE burned for a pass-holder renewal");

        // Renewed: paidThroughDay advanced (today + WINDOW_DAYS) and windowPaid CLEARED.
        assertGt(afKing.subscriptionOf(pass).paidThroughDay, _today(), "renewed window endpoint in the future");
        assertEq(afKing.subscriptionOf(pass).flags & 1, 0, "windowPaid cleared on a free extend");
    }

    /// @notice SUB-01: a NO-PASS subscriber at the day-31 renewal branch is CHARGED via the
    ///         all-or-nothing burnForKeeper (BurnieAutoExtracted, exactly `cost` burned, windowPaid
    ///         set), distinct from the pass-holder's free extend.
    function testRenewalNoPassChargedViaBurnForKeeper() public {
        address nopass = makeAddr("no_pass");
        uint256 cost = _subCost();
        _subscribeTicketMode(nopass, 1, /*fundBurnie*/ true); // funds BURNIE for the subscribe charge
        _approveKeeper(nopass);
        _fundPool(nopass, 1 ether);
        _fundBurnie(nopass, cost); // top up so the renewal charge has exactly enough
        _forceRenewalDue(nopass);

        uint256 burnieBefore = coin.balanceOf(nopass);

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_nopass"));
        afKing.autoBuy(50);

        // PAID extend taken: BurnieAutoExtracted emitted; NO free extend; exactly `cost` burned.
        assertEq(_countEvent(address(afKing), AUTO_EXTRACTED_SIG), 1, "no-pass charged via burnForKeeper");
        assertEq(_countEvent(address(afKing), EXTENDED_FREE_SIG), 0, "no-pass did NOT free-extend");
        assertEq(burnieBefore - coin.balanceOf(nopass), cost, "exactly the renewal cost burned");

        // Renewed: windowPaid SET, paidThroughDay advanced.
        assertEq(afKing.subscriptionOf(nopass).flags & 1, 1, "windowPaid set on a paid renewal");
        assertGt(afKing.subscriptionOf(nopass).paidThroughDay, _today(), "renewed window endpoint in the future");
    }

    // =========================================================================
    // Task 3b — burnForKeeper all-or-nothing (PROTO-02 / SUB-08)
    // =========================================================================

    /// @notice PROTO-02 / SUB-08: a no-pass subscriber whose spendable BURNIE is BELOW the renewal
    ///         cost has NOTHING burned (all-or-nothing), burnForKeeper returns 0, and the autoBuy
    ///         AUTO-PAUSES that sub (dailyQuantity 0, removed from the set, SubscriptionExpired)
    ///         WITHOUT reverting the whole autoBuy — a shortfall cannot strand a half-paid sub.
    function testRenewalShortfallBurnsNothingAndAutoPauses() public {
        // A HEALTHY paying sub so the autoBuy produces at least one buy and does not revert
        // NoSubscribersAutoBought (which would mask the auto-pause behavior of the shortfall sub).
        address healthy = makeAddr("healthy_payer");
        uint256 cost = _subCost();
        _subscribeTicketMode(healthy, 1, true);
        _approveKeeper(healthy);
        _fundPool(healthy, 1 ether);
        _fundBurnie(healthy, cost);
        _forceRenewalDue(healthy);

        // The SHORTFALL sub: funded BELOW cost so the all-or-nothing burn takes nothing.
        address shortfall = makeAddr("shortfall_payer");
        _subscribeTicketMode(shortfall, 1, true);
        _approveKeeper(shortfall);
        _fundPool(shortfall, 1 ether);
        _setBurnieBalance(shortfall, cost == 0 ? 0 : cost - 1); // strictly below cost
        _forceRenewalDue(shortfall);

        uint256 shortfallBurnieBefore = coin.balanceOf(shortfall);

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_shortfall"));
        afKing.autoBuy(50); // MUST NOT revert despite the shortfall sub

        // All-or-nothing: NOTHING burned from the shortfall player.
        assertEq(coin.balanceOf(shortfall), shortfallBurnieBefore, "shortfall: nothing burned (all-or-nothing)");

        // Auto-paused: SubscriptionExpired emitted, dailyQuantity zeroed, removed from the set.
        assertGe(_countEvent(address(afKing), SUB_EXPIRED_SIG), 1, "shortfall sub auto-paused (SubscriptionExpired)");
        assertEq(afKing.subscriptionOf(shortfall).dailyQuantity, 0, "shortfall sub dailyQuantity zeroed");
        assertEq(_subscriberIndexOf(shortfall), 0, "shortfall sub removed from the iterable set");

        // The healthy sub still renewed (the shortfall did not brick the autoBuy).
        assertEq(afKing.subscriptionOf(healthy).flags & 1, 1, "healthy sub still renewed (autoBuy not bricked)");
    }

    /// @notice PROTO-02 boundary: a no-pass subscriber funded EXACTLY at cost renews (windowPaid set,
    ///         exactly `cost` burned) — the all-or-nothing predicate is `>=`, so at-cost is a full burn.
    function testRenewalExactlyAtCostFullBurn() public {
        address atCost = makeAddr("at_cost");
        uint256 cost = _subCost();
        vm.assume(cost > 0);
        _subscribeTicketMode(atCost, 1, true);
        _approveKeeper(atCost);
        _fundPool(atCost, 1 ether);
        _setBurnieBalance(atCost, cost); // exactly cost
        _forceRenewalDue(atCost);

        vm.recordLogs();
        vm.prank(makeAddr("autoBuyer_atcost"));
        afKing.autoBuy(50);

        assertEq(_countEvent(address(afKing), AUTO_EXTRACTED_SIG), 1, "at-cost renews (full burn)");
        assertEq(coin.balanceOf(atCost), 0, "exactly cost burned, balance to zero");
        assertEq(afKing.subscriptionOf(atCost).flags & 1, 1, "windowPaid set at-cost");
    }

    // =========================================================================
    // Task 3c — Gas-pegged single-creditFlip autoBuy bounty (REW-02)
    // =========================================================================

    /// @notice REW-02: a autoBuy that processes >= 1 buying subscriber emits EXACTLY ONE creditFlip to
    ///         the autoBuyer (never per-item), gas-pegged off BOUNTY_ETH_TARGET. Drives two healthy
    ///         buying subs and asserts a single creditFlip to msg.sender of the expected amount.
    function testAutoBuyEmitsExactlyOneGasPeggedBounty() public {
        address s1 = makeAddr("buy_s1");
        address s2 = makeAddr("buy_s2");
        _setupHealthyBuyingSub(s1);
        _setupHealthyBuyingSub(s2);

        address autoBuyer = makeAddr("bounty_autoBuyer");
        uint256 mp = game.mintPrice();
        // Gas-pegged per-player bounty, scaled by the live stall multiplier; batchLen == 2 buys.
        uint256 mult = _stallMultiplier();
        uint256 expectedBounty = 2 * ((afKing.BOUNTY_ETH_TARGET() * PRICE_COIN_UNIT * mult) / mp);

        vm.recordLogs();
        vm.prank(autoBuyer);
        uint256 returned = afKing.autoBuy(50);

        // EXACTLY ONE creditFlip emission for the whole autoBuy (the bounty), to the autoBuyer.
        assertEq(_countCreditFlipTo(autoBuyer), 1, "exactly one bounty creditFlip per autoBuy tx (REW-02)");
        assertEq(returned, expectedBounty, "bounty == batchLen * gas-pegged per-player target (stall-scaled)");
        assertGt(returned, 0, "non-empty autoBuy pays a positive bounty");
        // Gas-pegged, NOT per-item: the single bounty is a flat batchLen * per-player target, so it
        // is independent of the per-player cost / mode (no measured-gas / per-item escalation).
        assertEq(
            returned / 2,
            (afKing.BOUNTY_ETH_TARGET() * PRICE_COIN_UNIT * mult) / mp,
            "per-player bounty is the flat gas-pegged target (never per-item measured gas)"
        );
    }

    /// @notice REW-02 tail: a autoBuy that processes ZERO buying subscribers reverts NoSubscribersAutoBought
    ///         (an atomic no-op for the caller — the structural disincentive against autoBuying nothing).
    ///         Here every active sub is forced AlreadyAutoBoughtToday so the loop produces no buys.
    function testZeroBuyAutoBuyRevertsNoSubscribersAutoBought() public {
        // Mark the two SUB-09 deploy subs (VAULT, SDGNRS) already-autoBought-today so they are skipped,
        // and add no buying sub — the autoBuy produces batchLen == 0.
        _markAutoBoughtToday(ContractAddresses.VAULT);
        _markAutoBoughtToday(ContractAddresses.SDGNRS);

        vm.prank(makeAddr("empty_autoBuyer"));
        vm.expectRevert(abi.encodeWithSignature("NoSubscribersAutoBought()"));
        afKing.autoBuy(50);
    }

    /// @notice Pre-loop guard: maxCount == 0 reverts EmptyAutoBuy (caller-bounded anti-gas-DoS floor).
    function testAutoBuyZeroMaxCountRevertsEmptyAutoBuy() public {
        vm.prank(makeAddr("zero_autoBuyer"));
        vm.expectRevert(abi.encodeWithSignature("EmptyAutoBuy()"));
        afKing.autoBuy(0);
    }

    // =========================================================================
    // Task 3d — OPEN-E cross-account subscribe-only auth (OPENE-04)
    // =========================================================================

    /// @notice OPENE-04 unapproved-source-refused: subscribing with an UNAPPROVED non-zero non-self
    ///         fundingSource reverts NotApproved at subscribe (the cross-account gate is checked HERE);
    ///         after the source approves the subscriber, the SAME subscribe is honored. Proves the
    ///         money-holder-grants-spender direction: S must approve M for M to draw from S.
    function testUnapprovedFundingSourceRefusedThenHonored() public {
        address s = makeAddr("auth_s");
        address m = makeAddr("auth_m");
        // S funds its own BURNIE for the window-1 burn (so only the AUTH gate, not a shortfall, governs).
        _fundBurnie(s, _subCost());

        // REFUSED: M has NOT been approved by S -> the non-zero non-self source reverts NotApproved.
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        afKing.subscribe(address(0), false, true, 1, 0, s);

        // S approves M on the game; now the SAME subscribe is honored (source stored, window-1 burn S).
        vm.prank(s);
        game.setOperatorApproval(m, true);
        uint256 sBefore = coin.balanceOf(s);
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, s);

        assertEq(afKing.subscriptionOf(m).fundingSource, s, "approved source honored (stored as S)");
        assertEq(sBefore - coin.balanceOf(s), _subCost(), "window-1 burn debited the approved source S");
    }

    /// @notice OPENE-04 revoke-does-NOT-stop-an-active-sub (subscribe-only auth): after S approves M
    ///         and M subscribes with fundingSource = S, S REVOKES (setOperatorApproval(M,false)). The
    ///         day-31 renewal STILL draws/burns from S — the keeper trusts the stored source and never
    ///         re-checks approval at renewal or per-draw. The sub is stopped only when S DEFUNDS
    ///         (spends down BURNIE -> day-31 auto-pause) or M cancels.
    function testRevokeDoesNotStopActiveSubButDefundDoes() public {
        address s = makeAddr("revoke_s");
        address m = makeAddr("revoke_m");
        // S funds BURNIE for the window-1 burn + the first renewal; M never holds BURNIE.
        _fundBurnie(s, _subCost() * 2);
        vm.prank(s);
        game.setOperatorApproval(m, true);
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, s); // source = S, window-1 burn from S
        _approveKeeper(m);
        _fundPool(s, 1 ether); // S funds the per-day ETH draw too
        _forceRenewalDue(m);

        // A healthy buying sub so each autoBuy produces >= 1 buy and never reverts NoSubscribersAutoBought
        // (which would mask the renewal/auto-pause behavior of M).
        address healthy1 = makeAddr("revoke_healthy_1");
        _setupHealthyBuyingSub(healthy1);

        // S REVOKES M's approval AFTER the sub is active.
        vm.prank(s);
        game.setOperatorApproval(m, false);
        assertFalse(game.isOperatorApproved(s, m), "S has revoked M");

        uint256 sBeforeRenewal = coin.balanceOf(s);

        vm.recordLogs();
        vm.prank(makeAddr("revoke_autoBuyer_1"));
        afKing.autoBuy(50);

        // SUBSCRIBE-ONLY AUTH: the day-31 renewal STILL burned S despite the revoke (no re-check).
        assertEq(_countEvent(address(afKing), AUTO_EXTRACTED_SIG), 1, "renewal still charged S after revoke");
        assertEq(_countEvent(address(afKing), SUB_EXPIRED_SIG), 0, "active sub NOT auto-paused by a revoke");
        assertEq(sBeforeRenewal - coin.balanceOf(s), _subCost(), "renewal burn STILL debits S (trust-the-sub)");
        assertGt(_subscriberIndexOf(m), 0, "M's sub stays in the set after S revokes");

        // Now S DEFUNDS (BURNIE drained to zero). Advance one keeper-local day so the autoBuy cursor
        // resets to 0 (re-reaching M, which the first autoBuy's advanced cursor moved past), then force
        // M renewal-due relative to the NEW today. The all-or-nothing burn takes nothing -> M
        // auto-pauses. This is the ONLY way the source halts an active sub.
        _setBurnieBalance(s, 0);
        vm.warp(block.timestamp + 1 days);
        _forceRenewalDue(m);

        // A healthy buyer so the defund autoBuy still produces a buy (it is the new keeper-local day, so
        // the cursor resets and every sub is re-evaluated).
        address healthy2 = makeAddr("revoke_healthy_2");
        _setupHealthyBuyingSub(healthy2);

        vm.recordLogs();
        vm.prank(makeAddr("revoke_autoBuyer_2"));
        afKing.autoBuy(50);

        assertGe(_countEvent(address(afKing), SUB_EXPIRED_SIG), 1, "defunded source -> day-31 auto-pause");
        assertEq(afKing.subscriptionOf(m).dailyQuantity, 0, "M's sub auto-paused once S defunds");
        assertEq(_subscriberIndexOf(m), 0, "M removed from the set on the defund auto-pause");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Live subscription cost in BURNIE = (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice.
    function _subCost() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * PRICE_COIN_UNIT) / game.mintPrice();
    }

    /// @dev Mirror of the autoBuy's SUB-03 stall-escalating multiplier (AfKing.sol:539-550): 1x base,
    ///      2x after 20 min, 4x after 1 hour, 6x after 2 hours, measured from day-start
    ///      (today * 1 days + 82620).
    function _stallMultiplier() internal view returns (uint256) {
        uint256 dayStart = uint256(_today()) * 1 days + 82_620;
        uint256 elapsed = block.timestamp > dayStart ? block.timestamp - dayStart : 0;
        if (elapsed >= 2 hours) return 6;
        if (elapsed >= 1 hours) return 4;
        if (elapsed >= 20 minutes) return 2;
        return 1;
    }

    /// @dev Subscribe `who` in ticket mode, dailyQuantity q. When fundBurnie, pre-funds enough BURNIE
    ///      for the (no-pass) subscribe-time all-or-nothing charge.
    function _subscribeTicketMode(address who, uint8 q, bool fundBurnie) internal {
        if (fundBurnie) _fundBurnie(who, _subCost());
        vm.prank(who);
        afKing.subscribe(address(0), false, true, q, 0, address(0)); // self-consent, ticket mode, no reinvest, self-funded
    }

    /// @dev A fully-healthy buying sub: ticket mode, operator-approved, funded pool + BURNIE, and
    ///      NOT due for renewal (paidThroughDay > today) so it skips straight to a clean purchase.
    function _setupHealthyBuyingSub(address who) internal {
        _subscribeTicketMode(who, 1, true);
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

    /// @dev Mint `amount` liquid BURNIE to `who` via the GAME-gated mintForGame path (keeps
    ///      totalSupply consistent so a later _burn does not underflow).
    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Force `who`'s BURNIE balance to an EXACT value via a direct slot write (slot 1). Used to
    ///      pin the shortfall / at-cost boundary precisely. (totalSupply is left as-is; these tests
    ///      assert balanceOf deltas, and the shortfall path burns nothing, so no underflow occurs;
    ///      the at-cost path burns exactly the written balance to zero.)
    function _setBurnieBalance(address who, uint256 bal) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BURNIE_BALANCE_SLOT)));
        vm.store(address(coin), slot, bytes32(bal));
    }

    /// @dev Grant `who` the permanent deity bit so hasAnyLazyPass(who) == true. Mirrors the game
    ///      constructor's VAULT/SDGNRS deity seeding: set bit HAS_DEITY_PASS_SHIFT (184) in
    ///      mintPacked_[who] (slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Force `who`'s sub into the day-31 renewal branch: write paidThroughDay <= today (set to
    ///      `today`, which is `<= today` so `sub.paidThroughDay <= today` is true) and clear
    ///      lastAutoBoughtDay so the AlreadyAutoBoughtToday skip does not fire first.
    function _forceRenewalDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        // Clear lastAutoBoughtDay (bytes 1..4) and paidThroughDay (bytes 5..8).
        uint256 mask = (uint256(0xFFFFFFFF) << (OFF_LASTSWEPT * 8)) | (uint256(0xFFFFFFFF) << (OFF_PAIDTHROUGH * 8));
        packed &= ~mask;
        // paidThroughDay = today (<= today -> renewal due); lastAutoBoughtDay = 0 (< today -> not skipped).
        packed |= (uint256(_today()) << (OFF_PAIDTHROUGH * 8));
        vm.store(address(afKing), slot, bytes32(packed));
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

    /// @dev Count events with `sig` emitted by `emitter` in the recorded logs.
    function _countEvent(address emitter, bytes32 sig) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == sig) count++;
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions whose indexed player == `to` (the bounty recipient).
    function _countCreditFlipTo(address to) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == to
            ) count++;
        }
    }
}
