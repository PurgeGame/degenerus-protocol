// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingSubscription -- Proves the testable acceptance of subscription correctness for the
///        AF_KING keeper: the pass-OR-pay renewal gate (SUB-01), the all-or-nothing burnForKeeper
///        charge (PROTO-02 / SUB-08), and the gas-pegged single-creditFlip sweep bounty (REW-02).
///
/// @notice Specifically:
///   - Pass-OR-pay (SUB-01): at the day-31 renewal branch a subscriber WITH an active lazy pass
///     (hasAnyLazyPass true) takes the FREE 30-day extend with NO burnForKeeper charge
///     (SubscriptionExtendedFree, windowPaid cleared); a subscriber WITHOUT a pass is charged via
///     the all-or-nothing burnForKeeper (BurnieAutoExtracted, windowPaid set).
///   - burnForKeeper all-or-nothing (PROTO-02 / SUB-08): a player with spendable BURNIE >= cost is
///     charged exactly `cost` and renews (windowPaid set, paidThroughDay reset); a player with
///     spendable < cost has NOTHING burned, burnForKeeper returns 0, and the sweep AUTO-PAUSES that
///     sub (dailyQuantity 0, removed from set, SubscriptionExpired) WITHOUT reverting the sweep.
///   - Bounty (REW-02): a sweep that processes >= 1 buying subscriber emits exactly ONE creditFlip
///     to the sweeper (msg.sender), gas-pegged (BOUNTY_ETH_TARGET-derived, never per-item); a sweep
///     that processes zero buys reverts NoSubscribersSwept.
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

    // Sub packed-field byte offsets within the single Sub slot.
    uint256 private constant OFF_DAILY = 0;       // uint8 dailyQuantity
    uint256 private constant OFF_LASTSWEPT = 3;   // uint32 lastSweptDay  (bytes 3..6)
    uint256 private constant OFF_PAIDTHROUGH = 7; // uint32 paidThroughDay (bytes 7..10)
    uint256 private constant OFF_FLAGS = 12;      // uint8 flags (bit 0 = windowPaid)

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
        vm.prank(makeAddr("sweeper_pass"));
        afKing.sweep(50);

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
        vm.prank(makeAddr("sweeper_nopass"));
        afKing.sweep(50);

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
    ///         cost has NOTHING burned (all-or-nothing), burnForKeeper returns 0, and the sweep
    ///         AUTO-PAUSES that sub (dailyQuantity 0, removed from the set, SubscriptionExpired)
    ///         WITHOUT reverting the whole sweep — a shortfall cannot strand a half-paid sub.
    function testRenewalShortfallBurnsNothingAndAutoPauses() public {
        // A HEALTHY paying sub so the sweep produces at least one buy and does not revert
        // NoSubscribersSwept (which would mask the auto-pause behavior of the shortfall sub).
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
        vm.prank(makeAddr("sweeper_shortfall"));
        afKing.sweep(50); // MUST NOT revert despite the shortfall sub

        // All-or-nothing: NOTHING burned from the shortfall player.
        assertEq(coin.balanceOf(shortfall), shortfallBurnieBefore, "shortfall: nothing burned (all-or-nothing)");

        // Auto-paused: SubscriptionExpired emitted, dailyQuantity zeroed, removed from the set.
        assertGe(_countEvent(address(afKing), SUB_EXPIRED_SIG), 1, "shortfall sub auto-paused (SubscriptionExpired)");
        assertEq(afKing.subscriptionOf(shortfall).dailyQuantity, 0, "shortfall sub dailyQuantity zeroed");
        assertEq(_subscriberIndexOf(shortfall), 0, "shortfall sub removed from the iterable set");

        // The healthy sub still renewed (the shortfall did not brick the sweep).
        assertEq(afKing.subscriptionOf(healthy).flags & 1, 1, "healthy sub still renewed (sweep not bricked)");
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
        vm.prank(makeAddr("sweeper_atcost"));
        afKing.sweep(50);

        assertEq(_countEvent(address(afKing), AUTO_EXTRACTED_SIG), 1, "at-cost renews (full burn)");
        assertEq(coin.balanceOf(atCost), 0, "exactly cost burned, balance to zero");
        assertEq(afKing.subscriptionOf(atCost).flags & 1, 1, "windowPaid set at-cost");
    }

    // =========================================================================
    // Task 3c — Gas-pegged single-creditFlip sweep bounty (REW-02)
    // =========================================================================

    /// @notice REW-02: a sweep that processes >= 1 buying subscriber emits EXACTLY ONE creditFlip to
    ///         the sweeper (never per-item), gas-pegged off BOUNTY_ETH_TARGET. Drives two healthy
    ///         buying subs and asserts a single creditFlip to msg.sender of the expected amount.
    function testSweepEmitsExactlyOneGasPeggedBounty() public {
        address s1 = makeAddr("buy_s1");
        address s2 = makeAddr("buy_s2");
        _setupHealthyBuyingSub(s1);
        _setupHealthyBuyingSub(s2);

        address sweeper = makeAddr("bounty_sweeper");
        uint256 mp = game.mintPrice();
        // Gas-pegged per-player bounty, scaled by the live stall multiplier; batchLen == 2 buys.
        uint256 mult = _stallMultiplier();
        uint256 expectedBounty = 2 * ((afKing.BOUNTY_ETH_TARGET() * PRICE_COIN_UNIT * mult) / mp);

        vm.recordLogs();
        vm.prank(sweeper);
        uint256 returned = afKing.sweep(50);

        // EXACTLY ONE creditFlip emission for the whole sweep (the bounty), to the sweeper.
        assertEq(_countCreditFlipTo(sweeper), 1, "exactly one bounty creditFlip per sweep tx (REW-02)");
        assertEq(returned, expectedBounty, "bounty == batchLen * gas-pegged per-player target (stall-scaled)");
        assertGt(returned, 0, "non-empty sweep pays a positive bounty");
        // Gas-pegged, NOT per-item: the single bounty is a flat batchLen * per-player target, so it
        // is independent of the per-player cost / mode (no measured-gas / per-item escalation).
        assertEq(
            returned / 2,
            (afKing.BOUNTY_ETH_TARGET() * PRICE_COIN_UNIT * mult) / mp,
            "per-player bounty is the flat gas-pegged target (never per-item measured gas)"
        );
    }

    /// @notice REW-02 tail: a sweep that processes ZERO buying subscribers reverts NoSubscribersSwept
    ///         (an atomic no-op for the caller — the structural disincentive against sweeping nothing).
    ///         Here every active sub is forced AlreadySweptToday so the loop produces no buys.
    function testZeroBuySweepRevertsNoSubscribersSwept() public {
        // Mark the two SUB-09 deploy subs (VAULT, SDGNRS) already-swept-today so they are skipped,
        // and add no buying sub — the sweep produces batchLen == 0.
        _markSweptToday(ContractAddresses.VAULT);
        _markSweptToday(ContractAddresses.SDGNRS);

        vm.prank(makeAddr("empty_sweeper"));
        vm.expectRevert(abi.encodeWithSignature("NoSubscribersSwept()"));
        afKing.sweep(50);
    }

    /// @notice Pre-loop guard: maxCount == 0 reverts EmptySweep (caller-bounded anti-gas-DoS floor).
    function testSweepZeroMaxCountRevertsEmptySweep() public {
        vm.prank(makeAddr("zero_sweeper"));
        vm.expectRevert(abi.encodeWithSignature("EmptySweep()"));
        afKing.sweep(0);
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

    /// @dev Mirror of the sweep's SUB-03 stall-escalating multiplier (AfKing.sol:539-550): 1x base,
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
        afKing.subscribe(address(0), false, true, q, 0); // self-consent, ticket mode, no reinvest
    }

    /// @dev A fully-healthy buying sub: ticket mode, operator-approved, funded pool + BURNIE, and
    ///      NOT due for renewal (paidThroughDay > today) so it skips straight to a clean purchase.
    function _setupHealthyBuyingSub(address who) internal {
        _subscribeTicketMode(who, 1, true);
        _approveKeeper(who);
        _fundPool(who, 1 ether);
    }

    /// @dev Approve AfKing as `who`'s game operator (the sweep's SUB-02 isOperatorApproved gate).
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
    ///      lastSweptDay so the AlreadySweptToday skip does not fire first.
    function _forceRenewalDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        // Clear lastSweptDay (bytes 3..6) and paidThroughDay (bytes 7..10).
        uint256 mask = (uint256(0xFFFFFFFF) << (OFF_LASTSWEPT * 8)) | (uint256(0xFFFFFFFF) << (OFF_PAIDTHROUGH * 8));
        packed &= ~mask;
        // paidThroughDay = today (<= today -> renewal due); lastSweptDay = 0 (< today -> not skipped).
        packed |= (uint256(_today()) << (OFF_PAIDTHROUGH * 8));
        vm.store(address(afKing), slot, bytes32(packed));
    }

    /// @dev Force `who`'s lastSweptDay = today so the AlreadySweptToday skip (reason 2) fires.
    function _markSweptToday(address who) internal {
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
