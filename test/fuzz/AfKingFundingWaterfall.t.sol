// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingFundingWaterfall -- Proves the AF_KING keeper's per-player funding waterfall (SUB-05)
///        and the two-tier pinned-identity funding-skip kill (SUB-06).
///
/// @notice Funding waterfall (SUB-05), inside the autoBuy per player:
///   - drainGameCreditFirst == false -> DirectEth, msgValue = cost (pays pool ETH only).
///   - drainGameCreditFirst == true:
///       * claimable cred > cost          -> Claimable, msgValue = 0 (pays from claimable only).
///       * 1 < cred <= cost               -> Combined,  msgValue = cost - (cred - 1) (pool tops up).
///       * cred <= 1                      -> DirectEth, msgValue = cost.
///   - _poolOf[player] < msgValue          -> InsufficientPool funding skip (the kill / exempt branch).
///   - Claimable-only degenerate (empty pool) is an EMERGENT property -- no `claimableOnly` flag: a
///     drain-first sub with cred > cost pays msgValue 0 and needs no pool; with cred <= cost and an
///     empty pool it funding-skips. There is no new flag for it.
///
/// @notice Two-tier skip-kill (SUB-06), on the InsufficientPool funding skip:
///   - a NORMAL sub is CANCELLED via swap-pop (dailyQuantity 0, windowPaid cleared,
///     SubscriptionExpired(player,1)), continuing WITHOUT advancing the cursor.
///   - the Vault and sDGNRS subs are EXEMPT -- they persist (no-op-and-retry, PlayerSkipped(player,3),
///     stay in the set), keyed on the UN-SPOOFABLE pinned ContractAddresses.VAULT / SDGNRS identity.
///   - a renewal LAPSE (the day-31 burnForKeeper shortfall, NOT a transient funding skip) still cancels
///     even Vault/sDGNRS -- the pinned-identity exemption guards ONLY the funding-skip branch.
///   - NO settable exemption flag exists: the exemption is purely the pinned-address equality branch.
///     A grep-clean assertion (vm.readFile) complements the runtime tests: zero isExempt / exemptFlag /
///     skipKillExempt / _exempt symbols in contracts/AfKing.sol.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live; the SUB-09 VAULT + SDGNRS
///      self-subscribes already in the set, drain-first + lootbox mode + qty 1). claimable is driven via
///      a direct write to DegenerusGame.claimableWinnings (slot 7); pool via depositFor; mode/approval via
///      the public mutators (vm.prank as the player, including VAULT/SDGNRS). Test-only: no contracts/*.sol
///      mutated -- the patched ContractAddresses.sol is restored via `git checkout` by the verify gate.
contract AfKingFundingWaterfall is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing 4-slot layout + Sub packed offsets, BurnieCoin balance slot, Game claimable slot
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 1;
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3;

    // Sub packed-field byte offsets re-derived from the post-OPEN-E repack (319.1-01 AFTER
    // layout): the two standalone bools collapsed into `flags` and a 20-byte `fundingSource`
    // address was appended, shifting lastAutoBoughtDay 3->1, paidThroughDay 7->5, flags 12->10.
    uint256 private constant OFF_DAILY = 0;          // uint8  dailyQuantity  (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;      // uint32 lastAutoBoughtDay    (bytes 1..4)
    uint256 private constant OFF_PAIDTHROUGH = 5;    // uint32 paidThroughDay  (bytes 5..8)
    uint256 private constant OFF_REINVEST = 9;       // uint8  reinvestPct     (byte 9)
    uint256 private constant OFF_FLAGS = 10;         // uint8  flags           (byte 10)
    uint256 private constant OFF_FUNDING_SOURCE = 11; // address fundingSource (bytes 11..30)
    uint256 private constant FLAG_WINDOW_PAID = 1;   // flags bit 0
    uint256 private constant FLAG_DRAIN_FIRST = 2;   // flags bit 1
    uint256 private constant FLAG_USE_TICKETS = 4;   // flags bit 2
    uint32 private constant WINDOW_DAYS = 30;

    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant BURNIE_BALANCE_SLOT = 1;     // BurnieCoin balanceOf mapping root
    uint256 private constant GAME_CLAIMABLE_SLOT = 7;     // DegenerusGame claimableWinnings mapping root

    bytes32 private constant SWEPT_SIG = keccak256("AutoBought(address,uint32,uint256)");
    bytes32 private constant SKIPPED_SIG = keccak256("PlayerSkipped(address,uint8)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    /// @dev Captured AutoBought stream: parallel arrays of player + the per-player cost (msgValue) slice, so
    ///      a single drain feeds both "which mode was chosen" (via msgValue) and "was it bought" assertions.
    address[] private _autoBoughtPlayer;
    uint256[] private _autoBoughtCost;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 3a -- Funding waterfall branches (SUB-05)
    // =========================================================================

    /// @notice DirectEth: a drainGameCreditFirst == FALSE sub pays the full cost from pool ETH
    ///         (msgValue == cost), independent of any claimable balance.
    function testWaterfallDirectEthWhenNotDraining() public {
        address p = _subscribeHealthy("direct_", /*drainFirst*/ false);
        uint256 cost = _cost(1);
        _setClaimable(p, cost * 5); // ample claimable -- IGNORED because drainFirst is false
        _fundPool(p, cost); // exactly the DirectEth msgValue

        _autoBuyCapture("direct_keeper");

        // Bought via DirectEth: AutoBought cost == full cost (msgValue == cost), pool fully debited.
        assertEq(_autoBoughtCostFor(p), cost, "DirectEth: msgValue == cost (full pool spend)");
        assertEq(afKing.poolOf(p), 0, "pool debited by the full cost");
    }

    /// @notice Claimable: a drain-first sub with claimable cred > cost pays from claimable ONLY
    ///         (msgValue == 0) -- no pool spend; an EMPTY pool still buys.
    function testWaterfallClaimableOnlyWhenCredExceedsCost() public {
        address p = _subscribeHealthy("claim_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, cost + 1); // cred > cost -> Claimable, msgValue 0
        // Deliberately leave the pool EMPTY: the claimable-only path needs no pool funding.
        assertEq(afKing.poolOf(p), 0, "pool empty for the claimable-only path");

        _autoBuyCapture("claim_keeper");

        // Bought via Claimable: AutoBought cost == 0 (msgValue 0); pool stayed empty (never touched).
        assertEq(_autoBoughtCostFor(p), 0, "Claimable: msgValue == 0 (no pool spend)");
        assertEq(afKing.poolOf(p), 0, "claimable-only path left the pool untouched (no new flag needed)");
    }

    /// @notice Combined: a drain-first sub with 1 < cred <= cost tops up from pool: msgValue ==
    ///         cost - (cred - 1). Proves the pool covers exactly the claimable shortfall (minus the
    ///         1-wei sentinel left behind).
    function testWaterfallCombinedTopsUpFromPool() public {
        address p = _subscribeHealthy("combo_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        uint256 cred = cost / 2 + 1; // 1 < cred <= cost (assuming cost > 2)
        vm.assume(cred > 1 && cred <= cost);
        _setClaimable(p, cred);
        uint256 expectedMsgValue = cost - (cred - 1);
        _fundPool(p, expectedMsgValue); // exactly the Combined top-up

        _autoBuyCapture("combo_keeper");

        // Bought via Combined: AutoBought cost == cost - (cred - 1); pool debited exactly that.
        assertEq(_autoBoughtCostFor(p), expectedMsgValue, "Combined: msgValue == cost - (cred - 1)");
        assertEq(afKing.poolOf(p), 0, "pool debited by exactly the Combined top-up");
    }

    /// @notice cred <= 1 sentinel: a drain-first sub whose claimable is only the 1-wei sentinel (or 0)
    ///         degrades to DirectEth (msgValue == cost) -- the `cred > 1` predicate excludes the
    ///         sentinel, so a drained-to-sentinel player pays full pool ETH.
    function testWaterfallSentinelClaimableDegradesToDirectEth() public {
        address p = _subscribeHealthy("sentinel_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, 1); // exactly the sentinel -> cred <= 1 -> DirectEth
        _fundPool(p, cost);

        _autoBuyCapture("sentinel_keeper");

        assertEq(_autoBoughtCostFor(p), cost, "sentinel claimable (cred<=1) degrades to DirectEth msgValue==cost");
        assertEq(afKing.poolOf(p), 0, "pool fully debited on the sentinel->DirectEth degrade");
    }

    /// @notice InsufficientPool: a drain-first NORMAL sub whose claimable + pool < cost funding-skips.
    ///         Here cred <= 1 (DirectEth, msgValue == cost) and pool < cost -> the skip fires. (The
    ///         NORMAL-sub consequence -- swap-pop cancel -- is asserted in Task 3b.)
    function testWaterfallInsufficientPoolWhenClaimablePlusPoolBelowCost() public {
        address p = _subscribeHealthy("insuf_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, 1); // sentinel -> DirectEth -> msgValue == cost
        _fundPool(p, cost - 1); // strictly below cost -> InsufficientPool

        // A second HEALTHY sub so the autoBuy produces >= 1 buy and does not revert NoSubscribersAutoBought.
        address healthy = _subscribeHealthy("insuf_healthy_", false);
        _fundPool(healthy, _cost(1));

        _autoBuyCapture("insuf_keeper");

        // The under-funded sub was NOT bought (funding skip); the healthy one was.
        assertEq(_autoBoughtCostFor(p), type(uint256).max, "under-funded sub NOT bought (InsufficientPool skip)");
        assertEq(_autoBoughtCostFor(healthy), _cost(1), "the healthy sub still bought (autoBuy not bricked)");
    }

    // =========================================================================
    // Task 3b -- Two-tier pinned-identity skip-kill (SUB-06)
    // =========================================================================

    /// @notice SUB-06 NORMAL kill: a NORMAL sub hitting a funding skip is CANCELLED via swap-pop --
    ///         dailyQuantity 0, removed from the set, SubscriptionExpired(player,1). The swap-pop occurs
    ///         WITHOUT advancing the cursor so a later occupant is still processed (proven elsewhere);
    ///         here we assert the cancel itself.
    function testNormalSubFundingSkipCancelsViaSwapPop() public {
        // A healthy sub guarantees the autoBuy produces a buy (avoids NoSubscribersAutoBought masking).
        address healthy = _subscribeHealthy("kill_healthy_", false);
        _fundPool(healthy, _cost(1));

        // The starved NORMAL sub: drain-first, sentinel claimable, pool below cost.
        address victim = _subscribeHealthy("kill_victim_", true);
        uint256 cost = _cost(1);
        _setClaimable(victim, 1);
        _fundPool(victim, cost - 1);
        assertGt(_subscriberIndexOf(victim), 0, "victim starts in the set");

        vm.recordLogs();
        vm.prank(makeAddr("kill_keeper"));
        afKing.autoBuy(50);
        _capture();

        // CANCELLED: SubscriptionExpired(victim,1), removed from set, dailyQuantity zeroed.
        assertEq(_countExpired(victim), 1, "NORMAL sub funding-skip -> SubscriptionExpired(.,1)");
        assertEq(_subscriberIndexOf(victim), 0, "NORMAL sub swap-popped out of the set");
        assertEq(afKing.subscriptionOf(victim).dailyQuantity, 0, "NORMAL sub dailyQuantity zeroed (auto-pause)");
        assertEq(afKing.subscriptionOf(victim).flags & uint8(FLAG_WINDOW_PAID), 0, "windowPaid cleared on the kill");
    }

    /// @notice SUB-06 EXEMPT: the VAULT and SDGNRS subs (already in the set via SUB-09) hitting the SAME
    ///         funding skip PERSIST -- PlayerSkipped(.,3), still in the set, NOT cancelled -- keyed on
    ///         the pinned ContractAddresses.VAULT / SDGNRS identity. A NORMAL sub in the identical
    ///         funding state IS cancelled, isolating the exemption to the pinned address.
    function testVaultAndSdgnrsExemptFromFundingSkipKill() public {
        // Make VAULT + SDGNRS reach the funding waterfall: approve the keeper (else NotApproved skip
        // reason 5 fires first) and put them in ticket mode (so the LootboxFloor skip cannot intercede),
        // drain-first. Leave their pool EMPTY and claimable at the sentinel so the DirectEth msgValue ==
        // cost cannot be funded -> the InsufficientPool branch fires for them.
        _prepExemptSub(ContractAddresses.VAULT);
        _prepExemptSub(ContractAddresses.SDGNRS);

        // A NORMAL sub in the IDENTICAL funding-skip state -> must be cancelled (the control).
        address normal = _subscribeHealthy("exempt_control_", true);
        _setClaimable(normal, 1);
        _fundPool(normal, _cost(1) - 1);

        // A healthy buyer so the autoBuy does not revert NoSubscribersAutoBought.
        address healthy = _subscribeHealthy("exempt_healthy_", false);
        _fundPool(healthy, _cost(1));

        uint256 countBefore = afKing.subscriberCount();

        vm.recordLogs();
        vm.prank(makeAddr("exempt_keeper"));
        afKing.autoBuy(50);
        _capture();

        // EXEMPT: VAULT + SDGNRS persist -- PlayerSkipped(.,3), still in the set, NOT expired.
        assertEq(_countSkipped(ContractAddresses.VAULT, 3), 1, "VAULT funding-skip -> PlayerSkipped(.,3) (exempt)");
        assertEq(_countSkipped(ContractAddresses.SDGNRS, 3), 1, "SDGNRS funding-skip -> PlayerSkipped(.,3) (exempt)");
        assertEq(_countExpired(ContractAddresses.VAULT), 0, "VAULT NOT cancelled on a funding skip");
        assertEq(_countExpired(ContractAddresses.SDGNRS), 0, "SDGNRS NOT cancelled on a funding skip");
        assertGt(_subscriberIndexOf(ContractAddresses.VAULT), 0, "VAULT stays in the set");
        assertGt(_subscriberIndexOf(ContractAddresses.SDGNRS), 0, "SDGNRS stays in the set");

        // CONTROL: the identically-starved NORMAL sub WAS cancelled -- the only difference is identity.
        assertEq(_countExpired(normal), 1, "the NORMAL control sub IS cancelled in the same funding state");
        assertEq(_subscriberIndexOf(normal), 0, "the NORMAL control sub is swap-popped out");

        // Net set change: -1 (only the NORMAL control left; VAULT/SDGNRS retained).
        assertEq(afKing.subscriberCount(), countBefore - 1, "only the NORMAL sub left the set; exempts retained");
    }

    /// @notice SUB-06 boundary: a RENEWAL lapse (the day-31 burnForKeeper shortfall, NOT a transient
    ///         funding skip) still CANCELS even the exempt VAULT/SDGNRS -- the pinned-identity exemption
    ///         guards ONLY the funding-skip branch, not the renewal-charge auto-pause. Forces VAULT into
    ///         the renewal branch (paidThroughDay <= today) with no pass and zero spendable BURNIE.
    function testRenewalLapseStillCancelsExemptSubs() public {
        // Prep VAULT to reach the renewal branch: approved + ticket mode, renewal-due, no pass, no BURNIE.
        _prepExemptSub(ContractAddresses.VAULT);
        _fundPool(ContractAddresses.VAULT, 100 ether); // ample pool -- so this is NOT a funding skip
        // VAULT/SDGNRS are seeded with the permanent deity pass in the game constructor (DegenerusGame
        // :214), so hasAnyLazyPass(VAULT) is TRUE and the renewal branch would FREE-extend (no charge,
        // no lapse). Clear the deity bit so the renewal hits the PAID all-or-nothing burnForKeeper path.
        _clearDeityPass(ContractAddresses.VAULT);
        _forceRenewalDue(ContractAddresses.VAULT);
        _setBurnieBalance(ContractAddresses.VAULT, 0); // all-or-nothing burn takes nothing -> lapse

        // A healthy buyer so the autoBuy does not revert NoSubscribersAutoBought.
        address healthy = _subscribeHealthy("lapse_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        vm.prank(makeAddr("lapse_keeper"));
        afKing.autoBuy(50);
        _capture();

        // The renewal LAPSE cancels VAULT despite the pinned-identity exemption (that exemption is
        // funding-skip-only). SubscriptionExpired(.,1), removed from set.
        assertEq(_countExpired(ContractAddresses.VAULT), 1, "renewal lapse cancels even VAULT (exemption is funding-skip-only)");
        assertEq(_subscriberIndexOf(ContractAddresses.VAULT), 0, "VAULT swap-popped on a renewal lapse");
    }

    // =========================================================================
    // Task 3c -- No settable exemption flag (grep-clean, complements the runtime tests)
    // =========================================================================

    /// @notice SUB-06 spoof-resistance: the exemption is the pinned-address equality branch ONLY. There
    ///         is NO setter / storage path that lets a NORMAL sub acquire the exemption. A source-level
    ///         grep over contracts/AfKing.sol finds zero settable-exemption-flag symbols, complementing
    ///         the runtime test that a NORMAL sub in the exempts' exact funding state IS cancelled.
    function testNoSettableExemptionFlagSymbol() public view {
        string memory src = vm.readFile("contracts/AfKing.sol");
        assertFalse(_contains(src, "isExempt"), "no isExempt symbol (no settable exemption flag)");
        assertFalse(_contains(src, "exemptFlag"), "no exemptFlag symbol");
        assertFalse(_contains(src, "skipKillExempt"), "no skipKillExempt symbol");
        assertFalse(_contains(src, "_exempt"), "no _exempt storage/path");
        // The ONLY exemption surface is the pinned-address equality -- assert that branch is present.
        assertTrue(_contains(src, "ContractAddresses.VAULT"), "the pinned-VAULT exemption branch exists");
        assertTrue(_contains(src, "ContractAddresses.SDGNRS"), "the pinned-SDGNRS exemption branch exists");
    }

    // =========================================================================
    // Task 3d -- OPEN-E shared funding source (OPENE-02/03 + LANDMINE A)
    // =========================================================================

    /// @notice OPENE-02/03 default-self equivalence: a sub with fundingSource == address(0) draws ETH
    ///         from and burns BURNIE against ITS OWN identity exactly as pre-OPEN-E -- the per-day ETH
    ///         draw debits the subscriber's own pool (AutoBought cost == cost, own pool zeroed) and the
    ///         subscribe-time window-1 burn came from the subscriber's own BURNIE. Byte-equivalence
    ///         baseline against which the cross-account cases below are the only behavioral delta.
    function testFundingSourceDefaultSelfIsByteEquivalent() public {
        address m = makeAddr("self_m");
        uint256 subCost = _subCost();
        uint256 burnieBefore = subCost + 7 ether; // ample own BURNIE; the window-1 burn debits self
        _fundBurnie(m, burnieBefore);

        // Self-funded subscribe (fundingSource == 0). hasAnyLazyPass(m) is false -> window-1 PAID burn.
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, address(0));
        vm.prank(m);
        game.setOperatorApproval(address(afKing), true);

        // Window-1 burn debited M's OWN BURNIE (self funding).
        assertEq(coin.balanceOf(m), burnieBefore - subCost, "default-self: window-1 burn from M's own BURNIE");
        // fundingSource stored as the self sentinel (address(0)).
        assertEq(afKing.subscriptionOf(m).fundingSource, address(0), "default-self: fundingSource == address(0)");

        uint256 cost = _cost(1);
        _fundPool(m, cost); // M funds its OWN pool

        _autoBuyCapture("self_keeper");

        // Per-day ETH draw debited M's OWN pool (self funding), exactly as pre-OPEN-E.
        assertEq(_autoBoughtCostFor(m), cost, "default-self: per-day draw debits M's own pool (DirectEth)");
        assertEq(afKing.poolOf(m), 0, "default-self: M's own pool fully debited");
    }

    /// @notice OPENE-02 cross-account ETH: a funded source S approves M; M subscribes with
    ///         fundingSource = S. The per-day ETH draw debits _poolOf[S], NOT _poolOf[M] -- M's own pool
    ///         is never touched. Exact-balance assertions on both pools isolate the routing.
    function testCrossAccountEthDrawsSourcePool() public {
        (address s, address m) = _approvedSourceSub("xeth_s", "xeth_m", /*fundSourceBurnie*/ true);
        uint256 cost = _cost(1);

        // Fund the SOURCE pool only; leave M's pool empty so a mis-routed draw would funding-skip.
        _fundPool(s, cost);
        assertEq(afKing.poolOf(m), 0, "M's own pool starts empty (only S funds)");

        _autoBuyCapture("xeth_keeper");

        // The draw debited S's pool, not M's. M bought via DirectEth at full cost from S's pool.
        assertEq(_autoBoughtCostFor(m), cost, "cross-account: M bought (DirectEth, cost forwarded)");
        assertEq(afKing.poolOf(s), 0, "cross-account ETH: S's pool debited by the full cost");
        assertEq(afKing.poolOf(m), 0, "cross-account ETH: M's own pool never touched");
    }

    /// @notice OPENE-03 cross-account BURNIE INCLUDING window-1: S approves M; M subscribes with
    ///         fundingSource = S and NO active pass, so the FIRST-window SUB-01 burn fires. That
    ///         window-1 burn debits S's BURNIE (not M's). Then forcing the day-31 renewal-due branch,
    ///         the auto-extract burn ALSO debits S. M holds zero BURNIE throughout -- proving S funds
    ///         both burn sites.
    function testCrossAccountBurnieFundsWindowOneAndRenewal() public {
        address s = makeAddr("xbur_s");
        address m = makeAddr("xbur_m");
        uint256 subCost = _subCost();

        // S holds the BURNIE for BOTH the window-1 and the day-31 renewal burns; M holds zero.
        _fundBurnie(s, subCost * 2);
        assertEq(coin.balanceOf(m), 0, "M holds zero BURNIE");

        // S approves M on the game (the OPEN-E cross-account gate honored at subscribe).
        vm.prank(s);
        game.setOperatorApproval(m, true);

        uint256 sBurnieBefore = coin.balanceOf(s);

        // M self-subscribes (subscriber == M) with fundingSource = S. No pass -> window-1 PAID burn.
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, s);

        // WINDOW-1: the first-window SUB-01 burn debited S's BURNIE, not M's.
        assertEq(coin.balanceOf(s), sBurnieBefore - subCost, "window-1 SUB-01 burn debits S (not M)");
        assertEq(coin.balanceOf(m), 0, "window-1: M's BURNIE untouched");
        assertEq(afKing.subscriptionOf(m).fundingSource, s, "fundingSource stored as S");

        // Approve the keeper for M and force the renewal-due branch for the day-31 auto-extract.
        vm.prank(m);
        game.setOperatorApproval(address(afKing), true);
        _fundPool(s, 100 ether); // ample S pool so the post-renewal buy is not a funding skip
        _forceRenewalDue(m);

        uint256 sBurnieBeforeRenewal = coin.balanceOf(s);

        vm.recordLogs();
        vm.prank(makeAddr("xbur_keeper"));
        afKing.autoBuy(50);
        _capture();

        // DAY-31 RENEWAL: the auto-extract burn ALSO debited S's BURNIE, not M's.
        assertEq(coin.balanceOf(s), sBurnieBeforeRenewal - subCost, "day-31 auto-extract burn debits S (not M)");
        assertEq(coin.balanceOf(m), 0, "day-31: M's BURNIE still untouched");
    }

    /// @notice OPENE-03 source BURNIE shortfall: with fundingSource = S approved but S holding BELOW
    ///         the window-1 cost, the all-or-nothing burnForKeeper takes nothing and the subscribe
    ///         REVERTS BurnieChargeFailed -- the source-shortfall falls through the existing failure
    ///         path (no half-paid sub).
    function testCrossAccountBurnieSourceShortfallRevertsSubscribe() public {
        address s = makeAddr("xshort_s");
        address m = makeAddr("xshort_m");
        uint256 subCost = _subCost();
        vm.assume(subCost > 0);

        _fundBurnie(s, subCost - 1); // strictly below the window-1 cost
        vm.prank(s);
        game.setOperatorApproval(m, true);

        vm.prank(m);
        vm.expectRevert(abi.encodeWithSignature("BurnieChargeFailed()"));
        afKing.subscribe(address(0), false, true, 1, 0, s);
    }

    /// @notice LANDMINE A -- exemption-spoof refusal: a NORMAL sub that sets fundingSource = VAULT does
    ///         NOT inherit the Vault never-cancel exemption. The exemption keys on the un-spoofable
    ///         SUBSCRIBER identity (player), never on the resolved source. On a funding skip the
    ///         spoofing sub is STILL cancelled via swap-pop, while the genuine VAULT self-sub stays.
    function testFundingSourceVaultDoesNotInheritExemption() public {
        // The spoofing NORMAL sub: VAULT approves the spoofer so fundingSource = VAULT is honored, but
        // drain-first + sentinel claimable + an EMPTY VAULT pool means the funding skip fires.
        // Fund VAULT's spendable BURNIE balance directly (the window-1 burn routes to the resolved
        // source = VAULT) so the subscribe SUCCEEDS and the sub reaches the autoBuy; the ETH-pool skip
        // is the surface under test. mintForGame(VAULT, .) routes to the virtual escrow reserve (NOT
        // balanceOf), so the window-1 burnForKeeper would see a zero spendable balance -- write
        // balanceOf[VAULT] directly instead. The day-31 path is not exercised here (this test is the
        // funding-skip surface, not renewal), so totalSupply drift from the direct write is irrelevant.
        address spoofer = makeAddr("spoof_m");
        _setBurnieBalance(ContractAddresses.VAULT, _subCost());
        vm.prank(ContractAddresses.VAULT);
        game.setOperatorApproval(spoofer, true); // VAULT approves spoofer -> source honored at subscribe
        vm.prank(spoofer);
        afKing.subscribe(address(0), /*drainFirst*/ true, true, 1, 0, ContractAddresses.VAULT);
        vm.prank(spoofer);
        game.setOperatorApproval(address(afKing), true);
        _setClaimable(spoofer, 1); // sentinel -> DirectEth msgValue == cost
        // Deliberately leave _poolOf[VAULT] empty -> the resolved-source pool read funding-skips.
        assertEq(afKing.poolOf(ContractAddresses.VAULT), 0, "VAULT pool empty -> spoofer's draw funding-skips");
        assertEq(afKing.subscriptionOf(spoofer).fundingSource, ContractAddresses.VAULT, "spoofer source = VAULT");
        assertGt(_subscriberIndexOf(spoofer), 0, "spoofer starts in the set");

        // A healthy buyer so the autoBuy does not revert NoSubscribersAutoBought.
        address healthy = _subscribeHealthy("spoof_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        vm.prank(makeAddr("spoof_keeper"));
        afKing.autoBuy(50);
        _capture();

        // LANDMINE A: the spoofing NORMAL sub IS cancelled (exemption keys on player, not source).
        assertEq(_countExpired(spoofer), 1, "fundingSource=VAULT spoofer STILL cancelled (LANDMINE A)");
        assertEq(_subscriberIndexOf(spoofer), 0, "spoofer swap-popped out of the set");
        assertEq(afKing.subscriptionOf(spoofer).dailyQuantity, 0, "spoofer dailyQuantity zeroed (auto-pause)");

        // The genuine VAULT self-sub (SUB-09) remains in the set -- only the real pinned identity is exempt.
        assertGt(_subscriberIndexOf(ContractAddresses.VAULT), 0, "genuine VAULT self-sub stays in the set");
        assertEq(_countExpired(ContractAddresses.VAULT), 0, "genuine VAULT NOT cancelled");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Set up a cross-account sub: source S (approves M on the game), subscriber M self-subscribes
    ///      in ticket mode (qty 1, drain-first FALSE -> DirectEth) with fundingSource = S, then approves
    ///      the keeper. When `fundSourceBurnie`, S is pre-funded the window-1 BURNIE so the no-pass
    ///      SUB-01 burn succeeds. M is NEVER given BURNIE -- the window-1 charge must come from S.
    function _approvedSourceSub(string memory sLabel, string memory mLabel, bool fundSourceBurnie)
        internal
        returns (address s, address m)
    {
        s = makeAddr(sLabel);
        m = makeAddr(mLabel);
        if (fundSourceBurnie) _fundBurnie(s, _subCost());
        vm.prank(s);
        game.setOperatorApproval(m, true); // S approves M -> fundingSource = S honored at subscribe
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, s); // ticket mode, qty 1, source = S
        vm.prank(m);
        game.setOperatorApproval(address(afKing), true);
    }

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Per-day cost for qty `q` = mintPrice * q (the keeper's effectiveQty * mp). Ticket mode.
    function _cost(uint256 q) internal view returns (uint256) {
        return game.mintPrice() * q;
    }

    function _subCost() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * PRICE_COIN_UNIT) / game.mintPrice();
    }

    /// @dev Subscribe a fresh player in TICKET mode (so the LootboxFloor skip cannot intercede), qty 1,
    ///      operator-approved, NOT renewal-due. `drainFirst` sets the funding waterfall mode.
    function _subscribeHealthy(string memory prefix, bool drainFirst) internal returns (address who) {
        who = makeAddr(string(abi.encodePacked(prefix, "p")));
        _fundBurnie(who, _subCost());
        vm.prank(who);
        afKing.subscribe(address(0), drainFirst, true, 1, 0, address(0)); // self, drainFirst, ticket mode, qty 1, self-funded
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
    }

    /// @dev Prep an existing SUB-09 sub (VAULT/SDGNRS) to REACH the funding waterfall: approve the
    ///      keeper (else NotApproved skip), switch to ticket mode (no LootboxFloor), drain-first, and
    ///      sentinel claimable so the DirectEth msgValue == cost. Pool left empty by the caller.
    function _prepExemptSub(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
        vm.prank(who);
        afKing.setMode(true); // ticket mode
        vm.prank(who);
        afKing.setDrainGameCreditFirst(true);
        _setClaimable(who, 1); // sentinel -> DirectEth
    }

    function _fundPool(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Force `who`'s DegenerusGame claimable winnings to `amount` (slot 7 mapping). Drives the
    ///      drain-first waterfall mode selection.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        vm.store(address(game), slot, bytes32(amount));
    }

    /// @dev Force `who`'s BURNIE balance (slot 1 mapping) to an exact value -- used to starve the
    ///      day-31 renewal charge for the renewal-lapse test.
    function _setBurnieBalance(address who, uint256 bal) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(BURNIE_BALANCE_SLOT)));
        vm.store(address(coin), slot, bytes32(bal));
    }

    /// @dev Force `who` into the day-31 renewal branch: paidThroughDay <= today, lastAutoBoughtDay cleared.
    function _forceRenewalDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        uint256 mask = (uint256(0xFFFFFFFF) << (OFF_LASTSWEPT * 8)) | (uint256(0xFFFFFFFF) << (OFF_PAIDTHROUGH * 8));
        packed &= ~mask;
        packed |= (uint256(_today()) << (OFF_PAIDTHROUGH * 8)); // paidThroughDay = today (<= today)
        vm.store(address(afKing), slot, bytes32(packed));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Clear `who`'s permanent deity-pass bit (shift 184) in DegenerusGame.mintPacked_ (slot 9) so
    ///      hasAnyLazyPass(who) is FALSE -- forces the renewal branch onto the PAID all-or-nothing
    ///      burnForKeeper path (the deity seeding at DegenerusGame :213-214 otherwise free-extends).
    function _clearDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev AutoBuy as a fresh keeper and drain the AutoBought stream into the parallel snapshot arrays.
    function _autoBuyCapture(string memory keeperLabel) internal {
        vm.recordLogs();
        vm.prank(makeAddr(keeperLabel));
        afKing.autoBuy(50);
        _capture();
    }

    /// @dev Drain the recorded logs ONCE into the parallel AutoBought(player,cost) snapshot. getRecordedLogs
    ///      empties the buffer, so a single drain feeds every count.
    function _capture() internal {
        delete _autoBoughtPlayer;
        delete _autoBoughtCost;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _capturedLogs = logs;
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(afKing) &&
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == SWEPT_SIG
            ) {
                _autoBoughtPlayer.push(address(uint160(uint256(logs[i].topics[1]))));
                // AutoBought(address indexed player, uint32 day, uint256 cost): non-indexed (day, cost) in data.
                (, uint256 cost) = abi.decode(logs[i].data, (uint32, uint256));
                _autoBoughtCost.push(cost);
            }
        }
    }

    /// @dev The full drained log set (for PlayerSkipped / SubscriptionExpired counts in the same drain).
    Vm.Log[] private _capturedLogs;

    /// @dev AutoBought cost (msgValue) for `who`, or type(uint256).max if `who` was NOT bought this autoBuy.
    function _autoBoughtCostFor(address who) internal view returns (uint256) {
        for (uint256 i; i < _autoBoughtPlayer.length; i++) {
            if (_autoBoughtPlayer[i] == who) return _autoBoughtCost[i];
        }
        return type(uint256).max;
    }

    /// @dev Count PlayerSkipped(who, reason) emissions in the captured drain.
    function _countSkipped(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _capturedLogs.length; i++) {
            Vm.Log memory L = _capturedLogs[i];
            if (
                L.emitter == address(afKing) &&
                L.topics.length >= 2 &&
                L.topics[0] == SKIPPED_SIG &&
                address(uint160(uint256(L.topics[1]))) == who
            ) {
                uint8 r = abi.decode(L.data, (uint8));
                if (r == reason) count++;
            }
        }
    }

    /// @dev Count SubscriptionExpired(who, _) emissions in the captured drain.
    function _countExpired(address who) internal view returns (uint256 count) {
        for (uint256 i; i < _capturedLogs.length; i++) {
            Vm.Log memory L = _capturedLogs[i];
            if (
                L.emitter == address(afKing) &&
                L.topics.length >= 2 &&
                L.topics[0] == SUB_EXPIRED_SIG &&
                address(uint160(uint256(L.topics[1]))) == who
            ) count++;
        }
    }

    /// @dev Substring search over the contract source (for the grep-clean exemption-flag assertion).
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }
}
