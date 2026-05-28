// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingFundingWaterfall -- Proves the AF_KING keeper's per-player funding waterfall (SUB-05),
///        the two-tier pinned-identity funding-skip kill (SUB-06), the OPEN-E shared funding source
///        ETH-routing (OPENE-02/03 + LANDMINE A), and the v50.0 pass-eviction-preserves-fundingSource
///        property (the new positive assertion replacing the v49 shortfall surface).
///
/// @notice Funding waterfall (SUB-05), inside the autoBuy per player:
///   - drainGameCreditFirst == false -> DirectEth, msgValue = cost (pays pool ETH only).
///   - drainGameCreditFirst == true:
///       * claimable cred > cost          -> Claimable, msgValue = 0 (pays from claimable only).
///       * 1 < cred <= cost               -> Combined,  msgValue = cost - (cred - 1) (pool tops up).
///       * cred <= 1                      -> DirectEth, msgValue = cost.
///   - _poolOf[player] < msgValue          -> InsufficientPool funding skip (the kill / exempt branch).
///
/// @notice Two-tier skip-kill (SUB-06), on the InsufficientPool funding skip:
///   - a NORMAL sub is CANCELLED via swap-pop (dailyQuantity 0, SubscriptionExpired(player,1)),
///     continuing WITHOUT advancing the cursor.
///   - the Vault and sDGNRS subs are EXEMPT -- they persist (no-op-and-retry, PlayerSkipped(player,3),
///     stay in the set), keyed on the UN-SPOOFABLE pinned ContractAddresses.VAULT / SDGNRS identity.
///   - NO settable exemption flag exists: the exemption is purely the pinned-address equality branch.
///
/// @notice v50.0 AFSUB / OPENE-04 four-protection re-attest:
///   - Consent-gate-at-subscribe: a non-zero non-self fundingSource MUST be operator-approved by the
///     source for the subscriber AT subscribe (the OPENE-04 gate at AfKing:391-399); no later
///     re-check (trust-the-sub temporal bound).
///   - Default-self byte-identical: subscribe with fundingSource = address(0) stores `fundingSource ==
///     address(0)` and the autoBuy resolves draw routing as `src = player` (self-pay) -- the per-day
///     ETH draw debits the subscriber's own pool. v50.0 AFSUB-01 removed the BURNIE-prepay window
///     entirely, so the only OPENE-02/03 routing surface remaining is the per-day ETH draw.
///   - No-escalation: a revoke AFTER subscribe does NOT escalate the OPENE-04 gate; the autoBuy
///     keeps debiting S's pool until S defunds.
///   - Trust-the-sub temporal bound: the sub is the consent unit (revoke is moot; the only way to
///     stop the source is M cancels or S defunds).
///
/// @notice v50.0 PASS-EVICTION-PRESERVES-FUNDINGSOURCE (the new positive assertion):
///   - At the AFSUB-03 EVICT branch the keeper writes `sub.dailyQuantity = 0; _removeFromSet(player);
///     emit SubscriptionExpired(player, 1)`. The Sub struct fields OTHER THAN dailyQuantity are NOT
///     deleted at eviction (only the cancel-tombstone reclaim path does `delete _subOf[player]`).
///     Concretely: a sub with `fundingSource = S` evicted at a level crossing leaves
///     `_subOf[player].fundingSource == S` readable post-eviction (the OPENE state survives the
///     pass-eviction path). Tested below.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live; the SUB-09 VAULT + SDGNRS
///      self-subscribes already in the set, drain-first + lootbox mode + qty 1). claimable is driven
///      via a direct write to DegenerusGame.claimableWinnings (slot 7); pool via depositFor; mode/
///      approval via the public mutators (vm.prank as the player, including VAULT/SDGNRS).
///      Test-only: no contracts/*.sol mutated.
contract AfKingFundingWaterfall is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing 4-slot layout + Sub packed offsets, BurnieCoin balance slot, Game claimable slot
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 1;
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3;

    // Sub packed-field byte offsets re-derived from the post-AFSUB layout: slot offset 5 is
    // repurposed in-place to `uint32 validThroughLevel` (v50.0 / Plan 335-04). The two standalone
    // bools were collapsed into `flags` (v47 OPENE-01) and a 20-byte `fundingSource` appended at 11.
    uint256 private constant OFF_DAILY = 0;             // uint8  dailyQuantity      (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;         // uint32 lastAutoBoughtDay  (bytes 1..4)
    uint256 private constant OFF_VALIDTHROUGHLEVEL = 5; // uint32 validThroughLevel  (bytes 5..8)
    uint256 private constant OFF_REINVEST = 9;          // uint8  reinvestPct        (byte 9)
    uint256 private constant OFF_FLAGS = 10;            // uint8  flags              (byte 10; bit 0 freed under AFSUB-01)
    uint256 private constant OFF_FUNDING_SOURCE = 11;   // address fundingSource     (bytes 11..30)
    uint256 private constant FLAG_DRAIN_FIRST = 2;      // flags bit 1
    uint256 private constant FLAG_USE_TICKETS = 4;      // flags bit 2

    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant BURNIE_BALANCE_SLOT = 1;     // BurnieCoin balanceOf mapping root
    uint256 private constant GAME_CLAIMABLE_SLOT = 7;     // DegenerusGame claimableWinnings mapping root

    bytes32 private constant SKIPPED_SIG = keccak256("PlayerSkipped(address,uint8)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    /// @dev GASOPT-04 oracle migration: the per-player `AutoBought(address,uint32,uint256)` event (whose
    ///      `cost` field carried the funding waterfall msgValue) is DELETED. The waterfall outcome is now
    ///      re-derived from STORAGE: "was it bought" = `lastAutoBoughtDay == today`; the charged ETH slice
    ///      = the funding-SOURCE pool delta across the autoBuy.
    mapping(address => uint256) private _srcPoolBefore;

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

        // Bought via DirectEth: charged cost == full cost (msgValue == cost), pool fully debited.
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

        // Bought via Claimable: charged cost == 0 (msgValue 0); pool stayed empty (never touched).
        assertEq(_autoBoughtCostFor(p), 0, "Claimable: msgValue == 0 (no pool spend)");
        assertEq(afKing.poolOf(p), 0, "claimable-only path left the pool untouched (no new flag needed)");
    }

    /// @notice Combined: a drain-first sub with 1 < cred <= cost tops up from pool: msgValue ==
    ///         cost - (cred - 1).
    function testWaterfallCombinedTopsUpFromPool() public {
        address p = _subscribeHealthy("combo_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        uint256 cred = cost / 2 + 1; // 1 < cred <= cost (assuming cost > 2)
        vm.assume(cred > 1 && cred <= cost);
        _setClaimable(p, cred);
        uint256 expectedMsgValue = cost - (cred - 1);
        _fundPool(p, expectedMsgValue); // exactly the Combined top-up

        _autoBuyCapture("combo_keeper");

        // Bought via Combined: charged cost == cost - (cred - 1); pool debited exactly that.
        assertEq(_autoBoughtCostFor(p), expectedMsgValue, "Combined: msgValue == cost - (cred - 1)");
        assertEq(afKing.poolOf(p), 0, "pool debited by exactly the Combined top-up");
    }

    /// @notice cred <= 1 sentinel: a drain-first sub whose claimable is only the 1-wei sentinel (or 0)
    ///         degrades to DirectEth (msgValue == cost).
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
    function testWaterfallInsufficientPoolWhenClaimablePlusPoolBelowCost() public {
        address p = _subscribeHealthy("insuf_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, 1); // sentinel -> DirectEth -> msgValue == cost
        _fundPool(p, cost - 1); // strictly below cost -> InsufficientPool

        // A second HEALTHY sub so the autoBuy produces >= 1 buy and is not a zero-buy no-op.
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
    ///         dailyQuantity 0, removed from the set, SubscriptionExpired(player,1).
    function testNormalSubFundingSkipCancelsViaSwapPop() public {
        // A healthy sub guarantees the autoBuy produces a buy (avoids a zero-buy no-op masking).
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
    }

    /// @notice SUB-06 EXEMPT: the VAULT and SDGNRS subs (already in the set via SUB-09) hitting the
    ///         SAME funding skip PERSIST -- PlayerSkipped(.,3), still in the set, NOT cancelled --
    ///         keyed on the pinned ContractAddresses.VAULT / SDGNRS identity. A NORMAL sub in the
    ///         identical funding state IS cancelled, isolating the exemption to the pinned address.
    /// @dev    Under v50.0 AFSUB-01 the SUB-09 deploy-time entries' VAULT/SDGNRS pass status
    ///         determines whether they reach the funding skip at all: VAULT carries the permanent
    ///         deity bit (DegenerusGame ctor) so VAULT's `lazyPassHorizon` is the deity sentinel and
    ///         VAULT's AFSUB-02 per-iter check is always satisfied (no crossing fires). SDGNRS holds
    ///         NO pass; under v50.0 the first autoBuy that reaches SDGNRS would hit the AFSUB-03
    ///         crossing branch and EVICT SDGNRS via tombstone BEFORE the funding-waterfall step --
    ///         which would moot the SDGNRS exemption assertion below. To preserve the SUB-06
    ///         exemption surface as the property under test, this helper re-grants the deity bit to
    ///         SDGNRS within the test fixture so SDGNRS' crossing check is also satisfied and the
    ///         funding skip is the only outcome. The pinned-identity exemption is independent of
    ///         pass state (it keys on the address equality branch), so this fixture-time fix-up
    ///         preserves the SUB-06 property under test without changing its meaning.
    function testVaultAndSdgnrsExemptFromFundingSkipKill() public {
        // v50.0 fixture fix: ensure SDGNRS' AFSUB-02 per-iter check is satisfied (deity sentinel)
        // so the test reaches the funding-waterfall step rather than evicting at the crossing.
        _grantDeityPass(ContractAddresses.SDGNRS);

        _prepExemptSub(ContractAddresses.VAULT);
        _prepExemptSub(ContractAddresses.SDGNRS);

        // A NORMAL sub in the IDENTICAL funding-skip state -> must be cancelled (the control).
        address normal = _subscribeHealthy("exempt_control_", true);
        _setClaimable(normal, 1);
        _fundPool(normal, _cost(1) - 1);

        // A healthy buyer so the autoBuy is not a zero-buy no-op.
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

    /// @notice SUB-06 boundary: a no-pass eviction at the AFSUB-03 crossing (the v50.0 analog of the
    ///         v49 day-31 BURNIE-shortfall lapse) STILL evicts even the exempt VAULT/SDGNRS subs if
    ///         their `lazyPassHorizon` no longer covers `currentLevel` -- the pinned-identity
    ///         exemption guards ONLY the funding-skip branch, NOT the pass-eviction branch. Forces
    ///         VAULT into the crossing branch with horizon < currentLevel (clear deity bit, leave
    ///         validThroughLevel = 0).
    function testPassEvictionStillCancelsExemptSubs() public {
        // Clear VAULT's permanent deity bit so its lazyPassHorizon = 0 (the AFSUB-03 evict precondition).
        _clearDeityPass(ContractAddresses.VAULT);
        _prepExemptSub(ContractAddresses.VAULT);
        // VAULT's pool ample so this is NOT a funding skip -- the crossing is the only path that
        // touches VAULT this autoBuy.
        _fundPool(ContractAddresses.VAULT, 100 ether);

        // Force the crossing: validThroughLevel = 0, bump game.level to 1 if needed.
        _forceCrossingDue(ContractAddresses.VAULT);

        // A healthy buyer so the autoBuy is not a zero-buy no-op.
        address healthy = _subscribeHealthy("crossing_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        vm.prank(makeAddr("crossing_keeper"));
        afKing.autoBuy(50);
        _capture();

        // The pass-eviction cancels VAULT despite the pinned-identity exemption (exemption is
        // funding-skip-only). SubscriptionExpired(.,1), removed from set.
        assertEq(_countExpired(ContractAddresses.VAULT), 1, "pass-eviction cancels even VAULT (exemption is funding-skip-only)");
        assertEq(_subscriberIndexOf(ContractAddresses.VAULT), 0, "VAULT swap-popped on a pass-eviction");
    }

    // =========================================================================
    // Task 3c -- No settable exemption flag (grep-clean, complements the runtime tests)
    // =========================================================================

    /// @notice SUB-06 spoof-resistance: the exemption is the pinned-address equality branch ONLY.
    ///         A source-level grep over contracts/AfKing.sol finds zero settable-exemption-flag
    ///         symbols.
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
    // Task 3d -- OPEN-E shared funding source (OPENE-02 ETH routing + LANDMINE A)
    // =========================================================================

    /// @notice OPENE-02/03 default-self equivalence: a sub with fundingSource == address(0) draws ETH
    ///         from ITS OWN pool, byte-equivalent to the pre-OPEN-E single-account flow.
    /// @dev    v50.0 AFSUB-01: subscribe no longer charges BURNIE, so the v49 "window-1 burn debits
    ///         self" assertion is gone -- the only OPENE-02/03 surface remaining is the per-day ETH
    ///         draw routing. The default-self byte-equivalence property reduces to: subscribe with
    ///         fundingSource = address(0) stores `fundingSource == address(0)` AND the autoBuy
    ///         resolves draw routing as `src = player` (self-pay).
    function testFundingSourceDefaultSelfIsByteEquivalent() public {
        address m = makeAddr("self_m");
        // Self-funded subscribe (fundingSource == 0). AFSUB-01: no BURNIE charge regardless of pass.
        vm.prank(m);
        afKing.subscribe(address(0), false, true, 1, 0, address(0));
        vm.prank(m);
        game.setOperatorApproval(address(afKing), true);

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
    ///         fundingSource = S. The per-day ETH draw debits _poolOf[S], NOT _poolOf[M].
    function testCrossAccountEthDrawsSourcePool() public {
        (address s, address m) = _approvedSourceSub("xeth_s", "xeth_m");
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

    /// @notice OPENE-04 / trust-the-sub temporal bound: S approves M, M subscribes with fundingSource = S,
    ///         S REVOKES approval AFTER subscribe. The autoBuy STILL draws ETH from S's pool -- the
    ///         keeper trusts the stored source and never re-checks approval at the per-day draw.
    function testRevokeDoesNotEscalatePerDayDraw() public {
        (address s, address m) = _approvedSourceSub("revoke_s", "revoke_m");
        uint256 cost = _cost(1);
        _fundPool(s, cost);

        // S REVOKES M's approval AFTER the sub is active.
        vm.prank(s);
        game.setOperatorApproval(m, false);
        assertFalse(game.isOperatorApproved(s, m), "S has revoked M");

        _autoBuyCapture("revoke_keeper");

        // The per-day draw STILL debited S's pool despite the revoke (no re-check at autoBuy).
        assertEq(_autoBoughtCostFor(m), cost, "trust-the-sub: per-day draw still debited S after revoke");
        assertEq(afKing.poolOf(s), 0, "S's pool drained by the trust-the-sub draw");
    }

    /// @notice LANDMINE A -- exemption-spoof refusal: a NORMAL sub that sets fundingSource = VAULT does
    ///         NOT inherit the VAULT never-cancel exemption. The exemption keys on the un-spoofable
    ///         SUBSCRIBER identity (player), never on the resolved source.
    function testFundingSourceVaultDoesNotInheritExemption() public {
        address spoofer = makeAddr("spoof_m");
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

        // A healthy buyer so the autoBuy is not a zero-buy no-op.
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
    // Task 3e -- v50.0 NEW: pass-eviction preserves fundingSource storage (AFSUB-03)
    // =========================================================================

    /// @notice v50.0 AFSUB-03: at the EVICT branch the keeper writes `sub.dailyQuantity = 0;
    ///         _removeFromSet(player); emit SubscriptionExpired(player, 1)` (AfKing._autoBuy:638-640).
    ///         The Sub struct's OTHER fields are NOT deleted -- only the cancel-tombstone reclaim path
    ///         (AfKing._autoBuy:601-609) does `delete _subOf[player]`. A sub evicted at the level
    ///         crossing therefore leaves `_subOf[player].fundingSource` readable post-eviction -- the
    ///         OPENE state survives the pass-eviction path. This is the positive assertion replacing
    ///         the v49 shortfall surface that Plan 335-04 Task 3 removed.
    /// @dev    Codifies the SUMMARY decision: Plan 335-04 chose `setDailyQuantity(0)`-style
    ///         tombstoning (NOT `delete _subOf[player]`) for the AFSUB-03 EVICT branch, so the
    ///         fundingSource field is preserved across eviction. The assertion below pins this
    ///         contract behavior; a future regression that switched eviction to a full delete would
    ///         flip this RED.
    function testPassEvictionPreservesFundingSourceStorage() public {
        (address s, address m) = _approvedSourceSub("eviction_s", "eviction_m");
        // No pass for M -> the AFSUB-03 EVICT branch fires at the crossing.
        // No deity bit granted (default).

        // Sanity: pre-eviction fundingSource is S.
        assertEq(afKing.subscriptionOf(m).fundingSource, s, "pre-eviction: fundingSource = S");

        // Drive the crossing for M: validThroughLevel = 0, currentLevel bumped to 1.
        _forceCrossingDue(m);
        _fundPool(s, 1 ether); // ample S pool so this is NOT a funding skip -- crossing is the path

        // A healthy buyer so the autoBuy is not a zero-buy no-op.
        address healthy = _subscribeHealthy("eviction_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        vm.prank(makeAddr("eviction_keeper"));
        afKing.autoBuy(50);
        _capture();

        // M evicted at the crossing (AFSUB-03), dailyQuantity zeroed, removed from set.
        assertEq(_countExpired(m), 1, "AFSUB-03: pass-eviction emitted SubscriptionExpired(.,1)");
        assertEq(_subscriberIndexOf(m), 0, "AFSUB-03: M swap-popped out of the set");
        assertEq(afKing.subscriptionOf(m).dailyQuantity, 0, "AFSUB-03: dailyQuantity zeroed (tombstoned)");

        // POSITIVE ASSERTION (the v50.0 new property): fundingSource SURVIVES the pass-eviction.
        // Plan 335-04 Task 3 chose setDailyQuantity(0)-style tombstoning (NOT delete _subOf[player])
        // for the EVICT branch, so OPENE state is preserved across eviction.
        assertEq(
            afKing.subscriptionOf(m).fundingSource,
            s,
            "AFSUB-03: pass-eviction preserves fundingSource storage (Plan 335-04 Task 3 chose tombstone, not delete)"
        );
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Set up a cross-account sub under v50.0 AFSUB-01: source S approves M on the game, M
    ///      self-subscribes with fundingSource = S, then approves the keeper. No BURNIE pre-funding
    ///      needed (AFSUB-01 removed the v49 window-1 burn). M's `validThroughLevel` is encoded as
    ///      lazyPassHorizon(M); for a fresh no-pass M this is 0 -- the test caller decides whether to
    ///      force a crossing or grant a pass.
    function _approvedSourceSub(string memory sLabel, string memory mLabel) internal returns (address s, address m) {
        s = makeAddr(sLabel);
        m = makeAddr(mLabel);
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

    /// @dev Subscribe a fresh player in TICKET mode (so the LootboxFloor skip cannot intercede), qty 1,
    ///      operator-approved. Under v50.0 AFSUB-01 there is no BURNIE pre-fund needed.
    function _subscribeHealthy(string memory prefix, bool drainFirst) internal returns (address who) {
        who = makeAddr(string(abi.encodePacked(prefix, "p")));
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

    /// @dev Force `who`'s DegenerusGame claimable winnings to `amount` (slot 7 mapping). Drives the
    ///      drain-first waterfall mode selection.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        vm.store(address(game), slot, bytes32(amount));
    }

    /// @dev Force `who` into the AFSUB-03 crossing branch: write validThroughLevel = 0, lastAutoBoughtDay = 0,
    ///      and bump `game.level` from 0 to 1 (if needed) so `currentLevel > sub.validThroughLevel`
    ///      is true at autoBuy time.
    /// @dev DegenerusGameStorage slot 0 layout: bytes 0..3 purchaseStartDay (uint32), bytes 4..7
    ///      dailyIdx (uint32), bytes 8..13 rngRequestTime (uint48), bytes 14..16 level (uint24).
    ///      Plan 335-06 helper-fix: write `level` at byte offset 14, not at bytes 0..2 (the v49-era
    ///      assumption that `level` lived at the low 24 bits was incorrect under the current Storage
    ///      packing).
    uint256 private constant LEVEL_BYTE_OFFSET = 14;
    function _forceCrossingDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        uint256 mask = (uint256(0xFFFFFFFF) << (OFF_LASTSWEPT * 8)) | (uint256(0xFFFFFFFF) << (OFF_VALIDTHROUGHLEVEL * 8));
        packed &= ~mask;
        vm.store(address(afKing), slot, bytes32(packed));
        // Ensure game.level > 0 so the crossing predicate (currentLevel > validThroughLevel = 0) is true.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (LEVEL_BYTE_OFFSET * 8);
        if (uint24((slot0 & levelMask) >> (LEVEL_BYTE_OFFSET * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (LEVEL_BYTE_OFFSET * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Grant `who` the permanent deity-pass bit so lazyPassHorizon(who) = type(uint24).max. Mirrors
    ///      the game constructor's VAULT/SDGNRS deity seeding: set bit HAS_DEITY_PASS_SHIFT (184) in
    ///      mintPacked_[who] (slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Clear `who`'s permanent deity-pass bit (shift 184) in DegenerusGame.mintPacked_ (slot 9) so
    ///      lazyPassHorizon(who) == 0 (assuming no frozenUntilLevel coverage) -- forces the AFSUB-03
    ///      EVICT branch at the crossing.
    function _clearDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev AutoBuy as a fresh keeper: snapshot every in-set sub's funding-source pool BEFORE the autoBuy
    ///      (the GASOPT-04 msgValue oracle — the source pool delta IS the charged slice), record logs,
    ///      run the autoBuy, then drain the PlayerSkipped/SubscriptionExpired stream.
    function _autoBuyCapture(string memory keeperLabel) internal {
        _snapshotSourcePools();
        vm.recordLogs();
        vm.prank(makeAddr(keeperLabel));
        afKing.autoBuy(50);
        _capture();
    }

    /// @dev Snapshot `_poolOf[src]` for the funding source of every in-set sub (src == self when
    ///      fundingSource is address(0)). The waterfall CEI debit moves exactly msgValue out of this pool,
    ///      so the pre/post delta reconstructs the per-player charged slice.
    function _snapshotSourcePools() internal {
        uint256 n = afKing.subscriberCount();
        for (uint256 i; i < n; i++) {
            address p = afKing.subscriberAt(i);
            address src = afKing.subscriptionOf(p).fundingSource;
            if (src == address(0)) src = p;
            _srcPoolBefore[p] = afKing.poolOf(src);
        }
    }

    /// @dev Drain the recorded logs ONCE into `_capturedLogs` (for PlayerSkipped / SubscriptionExpired
    ///      counts).
    function _capture() internal {
        _capturedLogs = vm.getRecordedLogs();
    }

    /// @dev The full drained log set (for PlayerSkipped / SubscriptionExpired counts in the same drain).
    Vm.Log[] private _capturedLogs;

    /// @dev The msgValue charged for `who` this autoBuy, re-expressed from the funding-SOURCE pool delta
    ///      (GASOPT-04). Returns type(uint256).max if `who` was NOT bought this autoBuy.
    function _autoBoughtCostFor(address who) internal view returns (uint256) {
        if (_lastAutoBoughtDayOf(who) != _today()) return type(uint256).max;
        address src = afKing.subscriptionOf(who).fundingSource;
        if (src == address(0)) src = who;
        return _srcPoolBefore[who] - afKing.poolOf(src);
    }

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot) — the buy oracle.
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
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
